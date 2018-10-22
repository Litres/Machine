package XPortal::Memcached;

use strict;
use utf8;
$ENV{PERL_LIBMEMCACHED_OPTIMIZE} = 1;
use Cache::Memcached::libmemcached qw{MEMCACHED_DISTRIBUTION_CONSISTENT};

my @MemcacheServers = (
  '127.0.01:11211'
);

my %Clusters = (
	R => undef,
	W => undef,
);
my @Servers;
my $DisableCache = 0;
#my $CachePrefix = 'new1:';
my $CachePrefix = '';
my $ReqCnt = 0;

sub ClusterOpt {
	return (
		#debug => $ServerID::DevelComp,
		#compress_threshold => 100_000,
		#compress_ratio => 0.9,
		distribution_method => MEMCACHED_DISTRIBUTION_CONSISTENT,
		no_block => 1,

		# тут вот описаны behavior_* https://metacpan.org/pod/Memcached::libmemcached::memcached_behavior
		# и тут из доков по libmemcached http://docs.libmemcached.org/memcached_behavior.html
		#behavior_use_udp => 1,
		#binary_protocol => 1,
		behavior_noreply => 1, # if you really don’t care about the result from your storage commands (set, add, replace, append, prepend)
		#behavior_server_failure_limit => 1,
		#behavior_auto_eject_hosts => 1, # DEPRECATED
		behavior_remove_failed_servers => 1, # выкидываем сервер из кластера
		behavior_retry_timeout => 3600,   # если выставить в разумное время, например 5 минут,
																			# то по прошествии этих 5 минут, помеченый дохлым сервер
																			# вернется в кластер, и так там и останется
																			# даже если он все-равно дохлый,
																			# и перераспределения ключей между живыми не произойдёт
																			# бага libmemcached видимо
		behavior_connect_timeout => 1,
		#behavior_ketama_weighted => 1,
		#debug => 1,
	);
}

sub GetClusterForType {
	my $Type = shift || 'R';
	return $Clusters{$Type} if $Clusters{$Type};

	$Clusters{$Type} = MyLibmemcachedWrapper->new({
      servers => \@MemcacheServers,
      ClusterOpt()
  });
}
sub ClusterR { GetClusterForType('R') }
sub ClusterW { GetClusterForType('W') }

sub GetAllClusters {
	if (1) {
		return ClusterW();
	}

	#return new ClusterMaster();
}

#sub GetServers {
#	return @Servers if @Servers;
#	for (@MemcacheServers){
#		push (@Servers,Cache::Memcached::libmemcached->new({
#				servers => [$_],
#				ClusterOpt()
#		}));
#	}
#	return @Servers;
#}

sub Disconnect{
	#PrintReqCntAndReset();
	for my $type (keys %Clusters){
		my $ClustersType = $Clusters{$type}->disconnect_all();
    delete $Clusters{$type};
	}
}


sub GetClusterHosts {
	return map {ref($_) ? $_->[0] : $_}
					grep {$_}
					@MemcacheServers;
}

sub MemKey {
	my $Key = shift;
	$Key =~ s/\s+/_/gs;
	return length($Key) > 240 ? XPortal::General::MD5Utf8($Key) : $Key;
}

sub ChkKey{
	return $_[0] if !$ServerID::DevelComp;
	my $key = shift;
	Carp::confess("[memcached] bad key : $key") if !$key || $key =~ /\s/ || length($key) > 255;
	return $key if $ServerID::ID eq 'PJ';
	$key .= ':'.$ServerID::ID;
	return $key;
}

sub DeleteCache{
	my $Key = ChkKey(shift);
	GetAllClusters()->delete($CachePrefix.$Key);
}
sub WriteCache {
	my $Key = shift;
	my $Value = shift;
	my $TTL = shift || 10*60;
	my $RewriteIfNotExists = shift || 0; # Like set(), but only stores in memcache if they key doesn't already exist.
	my $AllClusters = shift || 0; # write to ALL memcache server clusters
	unless ($Key){
		warn "[WARN] \$Key is uninitialized in WriteCache()";
		return;
	}
	if (!defined($Value)){
		my $err = "[ERR] \$Value is uninitialized in WriteCache()";
		if ($ServerID::DevelComp){
			Carp::confess($err);
		} else {
			my $caller = Carp::caller_info(0);
			$caller = $caller->{pack}.':'.$caller->{line};
			warn "$err : $caller";
			return;
		}
	}
	my $result;
	if ($DisableCache){
		DeleteCache($Key);
	} else {
		my $Claster;
		$Claster = $AllClusters ? GetAllClusters() : ClusterW();
		$Key = ChkKey($Key) if $ServerID::DevelComp;
		$Key = $CachePrefix.$Key if $CachePrefix;
		$result = $RewriteIfNotExists ? $Claster->add($Key,$Value,$TTL) : $Claster->set($Key,$Value,$TTL);
		#warn "[$$]w>>> $Key : ".(caller(1))[3];# : ".DDP::np($Value);
	}
	return $result;
}

sub IncrCache {
	my $Key = shift || return;
	my $TTL = 3600;

	my $result;
	$Key = ChkKey($Key) if $ServerID::DevelComp;
	$Key = $CachePrefix.$Key if $CachePrefix;
	# такие финты с add() из-за флага (behavior_noreply => 1)
	ClusterW()->add($Key,0,$TTL); #Like set(), but only stores in memcache if they key doesn't already exist.
	ClusterW()->incr($Key);

	return $result;
}

sub DecrCache {
	my $Key = shift || return;

	my $result;
	$Key = ChkKey($Key) if $ServerID::DevelComp;
	$Key = $CachePrefix.$Key if $CachePrefix;
	$result = ClusterW()->decr($Key);

	return $result;
}

sub ReadCache {
	my $key = ChkKey(shift);
	return if $DisableCache;
	$key = $CachePrefix.$key if $CachePrefix;
	#$ReqCnt++;
	my $Out = ClusterR()->get($key);
	return $Out;
}
sub ReadCacheMulti {
	my @Keys = @_;
	return if $DisableCache;
	if ($ServerID::DevelComp || $CachePrefix) {
		$_ = $CachePrefix.ChkKey($_) for (@Keys);
	}

	#$ReqCnt++;
	my $Out = ClusterR()->get_multi(@Keys);
	if ($ServerID::DevelComp && $ServerID::ID ne 'PJ' || $CachePrefix) {
		my $mcd = {};
		for my $k (keys %$Out){
			my $new_k = $k;
			$new_k =~ s/^$CachePrefix// if $CachePrefix;
			$new_k =~ s/:$ServerID::ID$//e if $ServerID::DevelComp && $ServerID::ID ne 'PJ';
			$mcd->{$new_k} = $Out->{$k};
		}
		$Out = $mcd;
	}

	return $Out;
}

sub FlushCache{
	ClusterW()->flush_all();
}

sub DisableCache{
	my $val = shift;
	$DisableCache = $val if (defined($val));
	return $DisableCache
}

sub PrintReqCntAndReset{
	warn "[MEMCACHED] request count: $ReqCnt";
	$ReqCnt = 0;
}

#sub ShowCacheForKey{
#	my $X = shift;
#	my $Key = $X->single_param('key');
#	unless ( &XPortal::General::IsDevelNet($X->{s}->{IPPool}) ){
#		$X->SetHTTPCode( 404 );
#		return;
#	}
#	$X->{s}->{BinOut} = 1;
#	binmode(STDOUT,':utf8');
#	$X->set_header('text/plain','utf-8','Cache-Control' => "no-cache");
#	my $Out = ReadCache($Key) if $Key;
#	if (defined($Out)) {
#		my $dumper = $ServerID::ID eq 'PJ' ? \&DDP::np : \&Data::Dumper::Dumper;
#		$Out = ref($Out) ? $dumper->($Out) : "||$Out||";
#	} else {
#		$Out = 'undef';
#	}
#
#	print "ReadCache($Key) = $Out";
#}
#
#$XPortal::Actions{'flush_cache'}=\&FlushCache;
#$XPortal::HackedUrls{'show_cache/'}=\&ShowCacheForKey;




#package ClusterMaster;
#
#sub new {
#	my $class = shift;
#  my $self = {};
#	bless $self;
#}
#
#sub AUTOLOAD {
#  return if our $AUTOLOAD =~ /::DESTROY$/;
#	my $self = shift;
#	my $metod;
#	{
#		local $1;
#		$AUTOLOAD =~ /^ClusterMaster::(\w+)$/;
#		$metod = $1;
#	}
#
#	foreach my $Farm (keys %XPortal::Settings::DataFarms) {
#		# это только для блэйдов ЛитРес
#		next unless index($Farm,'blade') == 0;
#		$Clusters{W}->{$Farm} = MyLibmemcachedWrapper->new({
#			servers => $XPortal::Settings::DataFarms{$Farm}->{'memcached'},
#			XPortal::Memcached::ClusterOpt()
#		}) unless $Clusters{W}->{$Farm};
#		$Clusters{W}->{$Farm}->$metod(@_);
#	}
#}

package MyLibmemcachedWrapper;

use strict;
use base 'Cache::Memcached::libmemcached';
use Scalar::Util qw(weaken);
use Data::MessagePack;

#my $mp = Data::MessagePack->new();
#$mp->canonical->utf8->prefer_integer;
#$mp->utf8;

sub new {
  my $self = shift->SUPER::new(@_);
  $self->{messagepack} = Data::MessagePack->new();
  $self->{messagepack}->utf8;
  return $self;
}

sub _mk_callbacks {
  my $self = shift;

  weaken($self);
  my $inflate = sub {
    my ($key, $flags) = @_;

    # print "start inflate key: " . $key . "\n";

    if ($flags & $self->SUPER::F_COMPRESS) {

      # print "has compress flag\n";

      if (! $self->SUPER::HAVE_ZLIB) {
        croak("Data for $key is compressed, but we have no Compress::Zlib");
      }
      $_ = Compress::Zlib::memGunzip($_);
    }

    if ($flags & $self->SUPER::F_STORABLE) {

      # print "has storable flag\n";

      $_ = $self->{messagepack}->unpack($_);
    }

    # print "end inflate key: " . $key . "\n";

    return ();
  };

  my $deflate = sub {
    # Check if we have a complex structure
    if (ref $_) {
      my $str = $_;

      # print "deflate string: " . $str . "\n";

      eval {
      	$_ = $self->{messagepack}->pack($_);
      };
      Carp::confess "$@\n=================\n||".DDP::np($str)."||\n" if $@;
      $_[1] |= $self->SUPER::F_STORABLE;
    }

    # Check if we need compression
    if ($self->SUPER::HAVE_ZLIB && $self->{compress_enable} && $self->{compress_threshold}) {
      # Find the byte length
      my $length = bytes::length($_);
      if ($length > $self->{compress_threshold}) {
        my $tmp = Compress::Zlib::memGzip($_);
        if (1 - bytes::length($tmp) / $length < $self->{compress_savingsS}) {
          $_ = $tmp;
          $_[1] |= $self->SUPER::F_COMPRESS;
        }
      }
    }
    return ();
  };
  return ($deflate, $inflate);
}


1;
