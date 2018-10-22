package MachineCPPSock;

use strict;
use utf8;
use Test::More;

use JSON::XS;
use IO::Socket::INET;
use IO::Socket::UNIX;

my $JSON = JSON::XS->new->pretty->allow_nonref->allow_blessed->utf8(1);


sub send_to_rmd {
  my $data = shift;
  my $TestConnect = shift || 0;
	my $socket = new IO::Socket::UNIX (
		Peer			=> '/var/fbhub/rmd.sock',
		Type => SOCK_STREAM,
	);
  ok($socket,'connect UNIX-socket') if $TestConnect;

	if (!$socket || $TestConnect){
    # нет UNIX-сокета попробуем tcp
    $socket = new IO::Socket::INET (
      PeerHost => 'localhost',
      PeerPort => '1071',
      Proto => 'tcp',
      Timeout	 => 1
    );
    ok($socket,'connect TCP-socket') if $TestConnect;
	}

	if ($socket) {
		my $dd = $JSON->encode($data);
		eval{
			$socket->send("$dd\n\cD\n");
		};

		if($@){
			$socket->shutdown(2);
      undef $socket;
		}
  }
  ok($socket,'sent data to rmd');
  return $socket;
}
  
sub get_from_rmd{
	my $socket = shift;
	my @json;
  if ($socket){
    eval {
      while (<$socket>) {
        last if ($_ eq "\cD\n");
        push @json, $_ if $_;
      }
      $socket->shutdown(2);
    };
    if ($@) {
      warn "[WARN] $@";
      @json = (); # что-то пошло не так
    }
  }
  if (@json){
    $json[-1] =~ s/\x04$//;
    pop(@json) unless $json[-1];
  }
  ok(scalar(grep {$_} @json),'get data from rmd');

	undef($socket);
	my $result;
	if (@json) {
    my $json_str = join('',@json);
		eval{
			$result = $JSON->decode($json_str) || {};
		};
		if ($@) {
      undef $result;
      warn "[ERR] $@\n=============\n=>|$json_str|<=\n=============\n";
		}
	}
  ok($result,'json-decode');
  if ($result){
    # в перловой машине есть служебные данные в результатах
    # они не должны влиять на успешность теста, удалим их
    delete $result->{cache_ttl} if exists($result->{cache_ttl});
    delete $result->{list}->{list_prepared}
      if exists($result->{list})
        && exists($result->{list}->{list_prepared});
  }
  #DDP::p($result);
	return $result;
}
