#!/usr/bin/perl

use strict;
use utf8;
use Test::More tests => 25;
use Test::More::UTF8;

use DDP;
use Clone;
use Digest::MD5;
use JSON::XS;
use POSIX;
use XPortal::Memcached;
use XPortal::CachedObject;
use MachineCPPSock;


=cut

Есть несколько уровней кэширования обработчика:
1) кэширование результата самого обработчика
2) кэширование результата самого обработчика вместе с его потомками


Для чтения из кэша машина мспользует оба уровня. Причем, если удалось прочитать из более высого уровня (2й),
то читать из более низкого (1й) нет смысла, т.к. В более высоком уровне кэширования уже содержатся данные
более низкого.

Для записи же в кэш машина использует только один наиболее высокий доступный уровень.
Если можно кэшировать данные обработчика виесте с данными его потомков (2й уровень),
то кэшировать отдельно самого обработчика (1й) не нужно.

Формирование ключа смотри в методах:
body_cache_key()  - ключ самого обработчика (1й уровень)
total_cache_key() - ключ для данных обработчика и потомков (2й уровень)

Для обработчика типа h_ есть отличия. В нем данные в кэш кладутся для каждого ID отдельно.
Ключ для этого дополняется в конце    ::<id>


Например в обработчике нужно работать с id: 123 и 456. Для обработчика сформировались ключи

body:52d03f338ab1de21ef4d22553abe060a   - body_cache_key()
total:f2a203299fef6e9c52f2d4e8ef25e71d  - total_cache_key()

Тогда для кэширования будут использоваться ключи:

total:f2a203299fef6e9c52f2d4e8ef25e71d::123
total:f2a203299fef6e9c52f2d4e8ef25e71d::456

или

body:52d03f338ab1de21ef4d22553abe060a::123
body:52d03f338ab1de21ef4d22553abe060a::456






=cut







my $JSON = JSON::XS->new->allow_nonref->allow_blessed->utf8(1);





my ($socket,$res,$d,$request, $expected);


# подготовим входные данные
my $input_data = {
  #debug => 1,
  request => {
    baz => 6,
    param => {
      foo => 2,
      profiler => 1,
    },
    Lib => 100,
    pager => {
      PageN          =>1,
      PageName       =>"new_books",
      PagesN         =>0,
      Post           =>"",
      PostParams     =>{},
      RecordsPerPage =>2,
      Rows           =>0,
      Start          =>0,
    }
  },
  other => {
    data => 'may be here'
  },
  user => {id => 128},
};



$request = {
	data => Clone::clone($input_data), # входные данны подключим тут
  body => {
    # обработчик L
    request => 'l_sql',
    params => {
      list_path => ['pepelats'],
      sql => ['dbl'
        ,'SELECT id, name, ddate
          FROM test_rmd
          WHERE id = ? OR id = ?
          ORDER BY id DESC'
        ,'ref.t1'
        ,3
      ],
      t1 => 'ref.data.request.param.foo',
      param2 => 'ref.data.request.baz',
      cache_salt => 'ref.data.cache_salt',
      #need_pager => 1,
      #'dump' => 'after_childs'
    },
    #cache_rels => ['Basket'],
  },
  childs => [{
    body => {
      # обработчик H2
      request => 'h_sql',
      cache_rels => ['User'], # отпечаток XPortal::CachedObject::Stamp::User
      params => {
        hash_of_lists => ['h2data'],
        sql => ['dbl'
          #,'!!! If you see this text, cache dont work !!!'
          ,'SELECT 3 AS id, " \"< #//" AS val, "h2" AS more_val'
        ],
        cache_salt => 'ref.data.cache_salt'
        #,'dump' => 'after_body'
      }
    },
    childs => [{
      body => {
        # обработчик H3
        request => 'h_sql',
        params => {
          sql => ['dbl'
            ,'SELECT art AS id, t
              FROM test_rmd_h3
              WHERE art IN (:ids)'
          ],
          cache_salt => 'ref.data.cache_salt'
          #,'dump' => 'before_body'
        }
      }
    }]
  },{
    body => {
      # обработчик H4
      request => 'h_sql',
      params => {
        sql => ['dbp'
          ,'SELECT test AS id, some_txt
            FROM test_rmd_h4
            WHERE test IN (:ids)'
        ],
        cache_salt => 'ref.data.cache_salt'
      }
    }
  }]
};


my $HashByID = {
        2 => {
          id    =>"2",
          name  => 'pluk',
          ddate => '2017-02-15 19:06:00'
        },
        3 => {
          id    =>"3",
          name  => 'roket',
          ddate => '1970-01-01'
        }
      };

my $LToCache = {
  data => {
    list =>{
      hash_by_id => $HashByID,
      ordered_list => [ map { $HashByID->{$_} } qw/3 2/ ],
      rows       => 2
    }
  }
};

## данные H2 обработчика вместе с дочерними для id=2
#my $H2TotalToCache_2 = {
#  data => {
#
#    # данный от обработчика H2
#    h2data => [
#      {
#        val => ' "< #//',
#        more_val => 'h2'
#      }
#    ],
#    
#    # данные от обработчика H3
#    t => 821
#
#  },
#
#  # id для которого эти данные мы закэшировали
#  id => 2
#};
#
#my $H2TotalExpected_3 = {
#  data => {
#
#    # данный от обработчика H2
#    h2data => [
#      {
#        val => -273
#      }
#    ],
#    
#    # данные от обработчика H3
#    t => 33
#
#  },
#
#  # id для которого эти данные мы закэшировали
#  id => 3
#};

my $H2BodyExpected_2 = {
  data => {}, # пустота
  # id для которого эти данные мы закэшировали
  id => 2
};

# данные только самого обработчика H2 для id=3
my $H2BodyToCache_3 = {
  data => {
    h2data => [
      {
        val => -273
      }
    ],
  },
  id => 3
};

# данные только самого обработчика H3 для id=3
my $H3BodyToCache_3 = {
  data => {
    h2data => [ # перезапишет данные от H2
      {
        val => 'drandulet'
      }
    ],
    t => 33
  },
  id => 3
};


CacheSalt($request);
$d = Clone::clone($request);

my $LBodyKey  = body_cache_key($d);
#my $LTotalKey = total_cache_key($d);


my $dd = mkChldById($d,0);
my $H2BodyKey  = body_cache_key($dd);

# в XPortal::Memcached используются разные хэндлы для записи и чтения
# и без ожидания подтверждения записи, поэтому может не быть в мемкэше отпечатка
# сразу после WriteCache
# Это нужно только для тестов
Time::HiRes::sleep(.2);

#my $H2TotalKey = total_cache_key($d->{childs}->[0]);

$dd = mkChldById($dd,0);
#DDP::p($dd); exit 0;
my $H3BodyKey  = body_cache_key($dd);
#my $H3TotalKey = total_cache_key($d->{childs}->[0]->{childs}->[0]);


memset($LBodyKey,$LToCache, 5);
memset($H2BodyKey.'::3',$H2BodyToCache_3, 5);
#memset($H2TotalKey.'::2',$H2TotalToCache_2, 5);
memset($H3BodyKey.'::3',$H3BodyToCache_3, 5);


#print $H2BodyKey,"\n",$H2TotalKey,"\n";



my $ResultExpected = {
  pepelats => [{
    ddate => "1970-01-01",
    h2data => [
      {
        val => 'drandulet'
      }
    ],
    id => 3,
    name => "roket",
    some_txt => "test_3",
    t => 33
  },{
    ddate => "2017-02-15 19:06:00",
    id => 2,
    name => "pluk",
    some_txt => "'/\\",
    t => 12
  }]
};


$socket = MachineCPPSock::send_to_rmd($request);
$res = MachineCPPSock::get_from_rmd($socket);
my $LBodyFromCache = memget($LBodyKey);
#my $LTotalFromCache = memget($LTotalKey);

#delete $LTotalFromCache->{data}->{cache_ttl}
#  if $LTotalFromCache && exists($LTotalFromCache->{data}) && exists($LTotalFromCache->{data}->{cache_ttl});

my $H2BodyFromCache_2 = memget($H2BodyKey.'::2');
my $H2BodyFromCache_3 = memget($H2BodyKey.'::3');
#my $H2TotalFromCache_2 = memget($H2TotalKey.'::2');
#my $H2TotalFromCache_3 = memget($H2TotalKey.'::3');

my $H3BodyFromCache_2 = memget($H3BodyKey.'::2');
my $H3BodyFromCache_3 = memget($H3BodyKey.'::3');
#my $H3TotalFromCache_2 = memget($H3TotalKey.'::2');
#my $H3TotalFromCache_3 = memget($H3TotalKey.'::3');

#DDP::p($res); exit 0;
#my $x = memget($H2BodyKey.'::2');
#DDP::p($H3BodyFromCache_2); exit 0;

is_deeply($LBodyFromCache, $LToCache, "L1 lvl 1 cache hasn't been changed");
#is_deeply($LTotalFromCache, {data => $ResultExpected}, 'L1 lvl 2 cache has been created');

is_deeply($H2BodyFromCache_2, $H2BodyExpected_2,"H2 lvl 1 cache has been created for id=2");
is_deeply($H2BodyFromCache_3, $H2BodyToCache_3, "H2 lvl 1 cache hasn't been changed for id=3");
#is_deeply($H2TotalFromCache_2, $H2TotalToCache_2, "H2 lvl 2 cache hasn't been changed for id=2");
#is_deeply($H2TotalFromCache_3, $H2TotalExpected_3, 'H2 lvl 2 cache has been created for id=3');

ok(defined($H3BodyFromCache_2),  "H3 lvl 1 cache has created for id=2");
is_deeply($H3BodyFromCache_3, $H3BodyToCache_3,  "H3 lvl 1 cache hasn't been changed for id=3");
#ok(!defined($H3TotalFromCache_2), "H3 lvl 2 cache hasn't created for id=2");
#is_deeply($H3TotalFromCache_3, { data => { t => 33 }, id => 3 }, 'H3 lvl 2 cache has been created for id=3');

is_deeply($res, $ResultExpected, 'result 1');












$ResultExpected = {
  pepelats => [{
    ddate => "2014-02-15 19:06:00",
    h2data => [{
      xml_text => '<h1>Tema</h1>'
    },{
      xml_text => '<ghost in="the shell"/>'
    }],
    id => 3,
    name => "roboti",
    some_txt => "test_3",
    t => 33
  },{
    ddate => "2017-02-15 19:06:00",
    h2data => [{
      xml_text => '<tt><boo var="661563"/></tt>'
    }],
    id => 2,
    name => "cheloveki",
    some_txt => "'/\\",
    t => 12
  }]
};

# исправим битый SQL
$request->{childs}->[0]->{body}->{params}->{sql}->[1] = 
"SELECT key1 AS id, xml_text
FROM test_rmd_h2
WHERE key1 IN (:ids)";

CacheSalt($request);
my $request2 = Clone::clone($request);
$d = Clone::clone($request);

$LBodyKey  = body_cache_key($d);
#$LTotalKey = total_cache_key($d);

$dd = mkChldById($d,0);
$H2BodyKey  = body_cache_key($dd);
#$H2TotalKey = total_cache_key($d->{childs}->[0]);

$dd = mkChldById($dd,0);
$H3BodyKey  = body_cache_key($dd);
#$H3TotalKey = total_cache_key($d->{childs}->[0]->{childs}->[0]);

$dd = mkChldById($d,1);
my $H4BodyKey  = body_cache_key($dd);
#my $H4TotalKey = total_cache_key($d->{childs}->[1]);

# H3 запретим кэшироваться
my $bRes = $request2->{childs}->[0]->{childs}->[0]->{body}->{result} ||= {};
$bRes->{cache_ignore} = 1;
$socket = MachineCPPSock::send_to_rmd($request2);
$res = MachineCPPSock::get_from_rmd($socket);
delete $res->{cache_ignore}; # это впринципе не обязательно


ok(defined(memget($LBodyKey)),    "L1: lvl 1 cache has been created");
#ok(!defined(memget($LTotalKey)),  "L1: lvl 2 cache hasn't been created");
ok( defined(memget($H2BodyKey.'::2'))  &&  defined(memget($H2BodyKey.'::3')),  "H2: lvl 1 cache has been created");
#ok(!defined(memget($H2TotalKey.'::2')) && !defined(memget($H2TotalKey.'::3')), "H2: lvl 2 cache hasn't been created");
ok(!defined(memget($H3BodyKey.'::2'))  && !defined(memget($H3BodyKey.'::3')),  "H3: lvl 1 cache hasn't been created (cache_ignore)");
#ok(!defined(memget($H3TotalKey.'::2')) && !defined(memget($H3TotalKey.'::3')), "H3: lvl 2 cache hasn't been created");
ok(defined(memget($H4BodyKey.'::2'))  && defined(memget($H4BodyKey.'::3')),  "H4: lvl 1 cache has been created");
#ok( defined(memget($H4TotalKey.'::2')) &&  defined(memget($H4TotalKey.'::3')), "H4: lvl 2 cache has been created");
is_deeply($res, $ResultExpected, 'result 2');









CacheSalt($request);
$request2 = Clone::clone($request);
$d = Clone::clone($request);

$LBodyKey  = body_cache_key($d);
#$LTotalKey = total_cache_key($d);

$dd = mkChldById($d,0);
$H2BodyKey  = body_cache_key($dd);
#$H2TotalKey = total_cache_key($d->{childs}->[0]);

$dd = mkChldById($dd,0);
$H3BodyKey  = body_cache_key($dd);
#$H3TotalKey = total_cache_key($d->{childs}->[0]->{childs}->[0]);

$dd = mkChldById($d,1);
$H4BodyKey  = body_cache_key($dd);
#$H4TotalKey = total_cache_key($d->{childs}->[1]);

$bRes = $request2->{childs}->[0]->{body}->{result} ||= {};
$bRes->{cache_denied} = 1;
$socket = MachineCPPSock::send_to_rmd($request2);
$res = MachineCPPSock::get_from_rmd($socket);
delete $res->{cache_denied}; # это впринципе не обязательно
#DDP::p($res);

ok(!defined(memget($LBodyKey)),    "L1: lvl 1 cache hasn't been created");
#ok(!defined(memget($LTotalKey)),  "L1: lvl 2 cache hasn't created");
ok(!defined(memget($H2BodyKey.'::2'))  && !defined(memget($H2BodyKey.'::3')),  "H2: lvl 1 cache hasn't been created");
#ok(!defined(memget($H2TotalKey.'::2')) && !defined(memget($H2TotalKey.'::3')), "H2: lvl 2 cache hasn't been created");
ok(!defined(memget($H3BodyKey.'::2'))  && !defined(memget($H3BodyKey.'::3')),  "H3: lvl 1 cache hasn't been created");
#ok(!defined(memget($H3TotalKey.'::2')) && !defined(memget($H3TotalKey.'::3')), "H3: lvl 2 cache hasn't been created");
ok(!defined(memget($H4BodyKey.'::2'))  && !defined(memget($H4BodyKey.'::3')),  "H4: lvl 1 cache hasn't been created");
#ok( defined(memget($H4TotalKey.'::2')) &&  defined(memget($H4TotalKey.'::3')), "H4: lvl 2 cache has been created");
is_deeply($res, $ResultExpected, 'result 3');

















































sub CacheSalt {
  my $d = shift;
  my $CacheSalt = time().int(rand(10000));
  print "new cache salt: $CacheSalt\n";
  $d->{data}->{cache_salt} = $CacheSalt;
}


######################################################################################
###################                                            ######################
###################    ФОРМИРОВАНИЕ КЛЮЧЕЙ ДЛЯ КЕШИРОВАНИЯ     ######################
###################                                            ######################
######################################################################################


# тут перечисляются дополнительные параметры,
# от которых зависит результат выполнения обработчиков
# для разных типов обработчиков (l_ или h_) он может отличаться
# но для l_sql и h_sql он совпадает, это ID БД
sub keys_for_cache{
	my $d = shift;
	# если мы работаем НЕ в dbh(r), dbstat, ddos то нужно добавить ID либы в ключ кэширования
	return $d->{data}->{request}->{Lib}
		if exists($d->{body}->{params}->{sql})
			&& $d->{body}->{params}->{sql}->[0] ne 'dbh'
			&& $d->{body}->{params}->{sql}->[0] ne 'dbhr'
      && $d->{body}->{params}->{sql}->[0] ne 'dbstat'
      && $d->{body}->{params}->{sql}->[0] ne 'ddos';
	return;
}


# Метод, формирующий ключ кэша для результата самого обработчика
sub body_cache_key{
	my $d = shift;
	my $parent_key = shift || '';
	my $body = $d->{body};

	# если мы уже пытались сформировать ключ, то вернем этот результат, каким бы он ни был
	# даже если в последствии откуда-то взялось $body->{result}->{cache_ignore}
	# это значит данные дочки нельзя кэшировать, свои то можно
	return $body->{cache_key} if $body && exists($body->{cache_key});
	$body->{cache_key} = '';

	# если кэширование запретили, то ничего не вернем
	return  if $d->{data}->{result}->{cache_denied}
          || $body->{result}->{cache_ignore}
          || $body->{result}->{cache_denied};

  # для начала пытаемся развернуть параметры, если требуется: ref.<что-то_там>
	# если все параметры удалось развернуть, то подмешивать ключ предка не нужно
	$parent_key = '' if resolve_body_param($d,'defined_only');
  # resolve_body_param возвращает true, если все параметры body.params определены

  my $s = join('::',
    $d->{data}->{request}->{cache_key_prefix} || (),
    $body->{request},
    # Digest::MD5 не умеет работать с перловым utf8
    $JSON->canonical->encode($body->{params}),
    $parent_key, # нужно подмешивать ключ предка, если не удалось развернуть ВСЕ параметры
    keys_for_cache($d),
    rels_cache_key($d)
  );

  # print "body_cache_key: input: " . $s . "\n";

  $body->{cache_key} = 'body:'.Digest::MD5::md5_hex($s);

  # print "body_cache_key: key: " . $body->{cache_key} . "\n";

	return $body->{cache_key};
}

# Метод, формирующий ключ кэша для результата самого обработчика и всех его потомков
sub total_cache_key{
	my $d = shift;
	my $parent_key = shift || '';
	my $body = $d->{body};

	# если кэширование запретили,
	# или нет ключа body_cache_key,
	# или ошибки сгенерились, то кэшировать нельзя
	return if !$body
					|| $body->{result}->{cache_ignore}
					|| $body->{result}->{cache_denied}
					|| $d->{data}->{result}->{cache_denied}
					|| !body_cache_key($d,$parent_key) # по идее, тут и будет сформирован body_cache_key
					#|| $d->error()
					#|| $d->fatal()
  ;

	# если мы уже формировали ключ, вернем результат, каким бы он ни был
	return $body->{total_cache_key} if exists($body->{total_cache_key});
	$body->{total_cache_key} = '';

	# ключ должен включать все дерево потомков
	my @childs_keys;
	if (exists($d->{childs})
				&& !(
						 exists($body->{result}->{total_cache_key})
							&& delete($body->{result}->{total_cache_key}) eq 'exclude_childs'
						)
	) {
		for (my $i=0; $i < scalar @{ $d->{childs} }; $i++){
			my $dd = make_child($d,$i);
			unless ($dd){ # мабуть мутация неудалась, а значит нельзя ключ высчитать
				return;
			}
			if (exists($dd->{body}) && exists($dd->{body}->{result}) && (
					$dd->{body}->{result}->{cache_ignore}
				|| $dd->{body}->{result}->{cache_denied}
			)){
				# если в одной из дочек нельзя кэшировать, то и нам нельзя и всем предкам тоже
				return;
			}
			my $child_total_key = total_cache_key($dd,body_cache_key($d));
			unless ($child_total_key) {
				# если полный ключ кэширования для одной из дочек составить не удалось -
				# то и у нас не получится
				return;
			}
			push(@childs_keys, $child_total_key);
		}
	}
	$body->{total_cache_key} = 'total:'.Digest::MD5::md5_hex(
															join('::',
																	 body_cache_key($d),
																	 @childs_keys
															)
													);
	return $body->{total_cache_key};
}










######################################################################################
################     Далее идут вспомогательные функции   ############################
######################################################################################

sub make_child {
	my $d = shift;
  my $i = shift;
  
  die "Unknown child: $i" unless exists($d->{childs}->[$i]) && exists($d->{childs}->[$i]->{body});
  $d->{childs}->[$i]->{data} = $d->{data};
  return $d->{childs}->[$i];
}

sub resolve_value_from_array {
	my $d = shift;
	my $path = shift || return;
	my $ref = shift || $d;
	my $store_value = shift || undef;

	shift(@$path) if scalar @$path && $path->[0] eq 'ref';
	return unless scalar @$path;
	my $k;
	while ($k = shift(@$path)) {
		if (ref($ref) eq 'ARRAY') {
			if ($k =~ /^\[(\-?\d+)\]$/) {
				if (!scalar(@$path) && defined($store_value)){
					$ref = $ref->[$1] = $store_value;
				} else {
					$ref = $ref->[$1];
				}
			} else {
				undef $ref;
				last;
			}
		} elsif (exists($ref->{$k})) {
			if (!scalar(@$path) && defined($store_value)){
				$ref = $ref->{$k} = $store_value;
			} else {
				$ref = $ref->{$k};
			}
		} elsif ($k =~ s/^\{ref//) {
			my @new_path;
			while ($k = shift(@$path)) {
				my $last = $k =~ s/\}$// ? 1 : 0;
				push(@new_path, $k);
				last if $last;
			}
			$k = resolve_value_from_array($d,\@new_path,undef,$store_value);
			$ref = $ref->{$k} if exists($ref->{$k});
		} elsif (defined($store_value)){
			$ref = $ref->{$k} = (scalar @$path ? {} : $store_value);
		} else {
			# Поломатый путь :(
			undef $ref;
			last;
		}
	}
	return $ref;
}

sub resolve_value {
	my $d = shift;
	my $str = shift || return;
	my $ref = shift || $d;
	my $delimiter = shift || qr/\./;
	my $store_value = shift || undef;

	my @path = split($delimiter,$str);
	resolve_value_from_array($d,\@path,$ref,$store_value);
}

sub param_value{
	my $d = shift;
	my $param = shift;
	my $ref = shift;
	return $param if ref($param) || !$param;
	my $p;
	for (split(/\s*\|\s*/,$param)){
		$p = $_; # это магия, если просто подставить в for, то не работает
		my $i = 0;
		while ($p =~ s/^ref\.// && ++$i<10){
			$p = resolve_value($d,$p,$ref);
		}
		if ($i>=10) {
			$p = undef;
			die("[ERR] exceeded inside referrer $i");
		}
		last if $p;
	}
	return $p;
}

sub resolve_body_param{
	my $d = shift;
	my $defined_only = shift || 0;
	my $body = $d->{body};
	my $AllResolved = 1;
	if ($body->{params}) {
		for my $k (keys %{$body->{params}}){
			my $val = param_value($d,$body->{params}->{$k});
			if (defined($val) || !$defined_only){
				$body->{params}->{$k} = $val;
			} elsif ($AllResolved){
				$AllResolved = '';
			}
		}
		mk_pager_limit($d);
	}
	return $AllResolved;
}


sub rels_cache_key{
	my $d = shift;
	return unless $d->{body}->{cache_rels};

  #Если в cache_rel указан отпечаток, со списоком парамаметров. Переносим из из body: rel_id
  # cache_rels => [{'UserFollowers'=>['rel_id']}]
  my $Params={};
  my $CacheRelsNames=[];
  for (@{$d->{body}->{cache_rels}}) {
    if (ref($_) eq 'HASH') {
      my $Name=(keys (%{$_}))[0];
      foreach my $ParamFromBody (@{$_->{$Name}}) {
        if (not defined $d->{body}->{params}->{$ParamFromBody}) {
         $d->fatal("Cache_rels param not found");
         return;
        }
        $Params->{$ParamFromBody}=$d->{body}->{params}->{$ParamFromBody};
      }
      push (@$CacheRelsNames,$Name);
    } else {
     push (@$CacheRelsNames,$_);
    }
  }

  # создадим объект, которые ничего не достает и не сохраняет в мемкеш,
	# но чекает зависимые отпечатки
  $d->{data}->{user}->{ID} = $d->{data}->{user}->{id};
  my $ChkStamps = new XPortal::CachedObject::ChkStampTime({
    %{$Params},
    X => { # там нужно окружение
      s => $d->{data}->{request},
      u => $d->{data}->{user},
    },
    relations => $CacheRelsNames
  });
	return $ChkStamps->GetCacheKey();
}

sub not_found_token {
	return 'cache_not_found_body' if $_[1] eq 'body';
	return 'cache_not_found_all' if $_[1] eq 'all';
	return 'cache_not_found_body+childs+processor' if $_[1] eq 'body+childs+processor';
	$_[0]->fatal('unknown type');
	return;
}


######################################################################################
######################################################################################
######################################################################################






























# этот метод добавляет в body.params параметр limit => [start, number],
# где start  - это стартовое значение для пагинатора
#     number - кол-во выбираемыж строк обработчиком
# данные формируются из окружения data.request.pager и только при наличии в body.params параметра need_pager
# Пример данных из окружения data.request.pager
#{
#  404            =>"",
#  DB             =>"dbl",
#  NeedQ          =>0,
#  OutType        =>"Hash",
#  PageN          =>1,
#  PageName       =>"new_books",
#  PagesN         =>0,
#  PeriodEnd      =>"2018-05-10 17:08:59",
#  PeriodStart    =>"2018-04-09 17:08:59",
#  Post           =>"",
#  PostParams     =>{},
#  RecordsPerPage =>12,
#  Rows           =>0,
#  skip_cookie_RPP=>1,
#  Start          =>0,
#  URL            =>"/pages/new_books/"
#}
# need_pager встречается только у обработчиков типа l_.
sub mk_pager_limit{
	my $d = shift;
	my $BParams = $d->{body}->{params};
	my $ParamPager;
	$ParamPager = $BParams->{need_pager} if $BParams && exists($BParams->{need_pager});

	if ($ParamPager && !exists($BParams->{limit})) {
		if (ref($ParamPager) ne 'HASH') {
			$BParams->{limit} = [$d->{data}->{request}->{pager}->{Start}, $d->{data}->{request}->{pager}->{RecordsPerPage}];
		} else {
			my $PagerRecordsPerPage = exists($ParamPager->{RecordsPerPage}) && defined($ParamPager->{RecordsPerPage})
					? $ParamPager->{RecordsPerPage}
					: $d->{data}->{request}->{pager}->{RecordsPerPage};
			my $PagerStart = exists($ParamPager->{Start}) && defined($ParamPager->{Start})
					? $ParamPager->{Start}
					: exists($ParamPager->{RecordsPerPage}) && defined($ParamPager->{RecordsPerPage})
					? (($d->{data}->{request}->{pager}->{PageN} > 1 ? $d->{data}->{request}->{pager}->{PageN} : 1) - 1)*$ParamPager->{RecordsPerPage}
					: $d->{data}->{request}->{pager}->{Start};
			$BParams->{limit} = [$PagerStart, $PagerRecordsPerPage];
		}
	}
}


# need_pager может быть как хэшем, так и числом
#sub mk_pager{
#	my $d = shift;
#	my $Rows = shift || $d->{body}->{result}->{list}->{rows} || 0;
#	my $Pager = Clone::clone($d->{data}->{request}->{pager});
#
#	my $ParamPager = $d->{body}->{params}->{need_pager};
#	if (ref($ParamPager) eq 'HASH'){
#		# в need_pager передан хэш с дополнительными параметрами - используем их
#		$Pager->{$_} = $ParamPager->{$_} for keys %$ParamPager;
#		$Pager->{Rows} = $Rows unless exists($ParamPager->{Rows});
#	} elsif ($ParamPager > 1) {
#		$Pager->{Rows} = $ParamPager;
#	} else {
#		$Pager->{Rows} = $Rows;
#	}
#
#	$Pager = PagerGetHash($Pager);
#	$d->error(404) if delete ($Pager->{404});
#	my @path;
#	if (exists($d->{body}->{params}->{list_path})) {
#		if (ref($d->{body}->{params}->{list_path}) eq 'ARRAY'){
#			push (@path, @{ $d->{body}->{params}->{list_path} });
#			pop @path; # последний элемент не надо
#		}
#	}
#	push(@path, 'pager');
#	$d->resolve_value_from_array(\@path,$d->{body}->{result},$Pager);
#	return;
#}

my $Default =	{
	'RecordsPerPage' => 12,
	'PageN' => 1,
	'Start' => 0,
	'PagesN' => 0,
	'NeedQ' => 0,
	'Rows' => 0,
	'URL' => '',
	'PageName' => '',
	'PeriodStart' => '',
	'PeriodEnd' => '',
	'Post' => '',
	'PostParams' => {},
	'DB' => 'dbl',
	'404' => '',
	'OutType' => 'XML',
};

sub PagerGetHash{
	my $self = shift;
	die "[ERR] not enough data for paginator" unless defined( $self->{'Rows'} ) && $self->{'RecordsPerPage'};

  $self->{'PagesN'} = POSIX::ceil(($self->{'Rows'}/$self->{'RecordsPerPage'})) unless $self->{'PagesN'};
	$self->{'404'} = 404 if (($self->{'PagesN'} > 0 || $self->{'PageN'} > 1) &&
																		 $self->{'PageN'} > $self->{'PagesN'});
	my $pagerhash = {
			page       => $self->{'PageN'},
			pages      => $self->{'PagesN'},
      postparams => XPortal::General::FixText(GetPostParams($self), undef, 1),
			post       => XPortal::General::FixText($self->{'Post'}, undef, 1),
			limit      => $self->{'RecordsPerPage'},
			rows			 => $self->{'Rows'}
	};
	$pagerhash->{lc($_)} = $self->{$_} foreach (qw/URL NeedQ PageName Rows/);

	for my $k (keys %{$self}){
		unless(exists($Default->{$k})){ $pagerhash->{$k} = $self->{$k}; }
	}
	return $pagerhash;
}

sub GetPostParams {
  my $self = shift;
  my $arg = shift || {param_glue => ',', val_glue => ','};
  my $postParams = '';
  foreach my $param (keys %{$self->{'PostParams'}}) {
    $postParams .= $postParams ? $arg->{param_glue} : '';
    if (ref($self->{'PostParams'}->{$param}) eq 'ARRAY') {
      $postParams .= join $arg->{param_glue} => map { $param . $arg->{val_glue} . $_ } @{$self->{'PostParams'}->{$param}};
    } else {
      $postParams .= $param . $arg->{val_glue} . $self->{'PostParams'}->{$param};
    }
  }
  return $postParams;
}

sub mkChldById {
  my ($d, $id) = @_;
  return unless exists($d->{childs}) && exists($d->{childs}->[0]);
  $d->{childs}->[0]->{data} = $d->{data};
  return $d->{childs}->[0];
}


sub memset{
  XPortal::Memcached::WriteCache(@_);
}

sub memget{
  my $key = shift;
  # print "memcached get: " . $key . "\n";
  XPortal::Memcached::ReadCache($key);
}
