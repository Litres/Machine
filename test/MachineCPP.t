use strict;
use utf8;
use Test::More tests => 13;

use DDP;
use Clone;
use JSON::XS;
use IO::Socket::INET;
use IO::Socket::UNIX;

#binmode STDOUT, ':utf8';
#binmode STDERR, ':utf8';

my $JSON = JSON::XS->new->pretty->allow_nonref->allow_blessed->utf8(1);

# подготовим входные данные
my $input_data = {
  request => {
    baz => 6,
    param => {
      foo => 1
    },
    Lib => 100
  },
  other => {
    data => 'may be here'
  }
};

# запрос на выбор из БД l_
my $request = {
  body => {
    request => 'l_sql', # имя инструкции для машины, по нему машина понимает, что нужно делать
    params => {
      # параметры для инструкции
      # Если значение параметра строка, начинающаяся на 'ref.',
      # значит данные лежат в хэше $request по указанному пути
      # например ref.data.request.baz это $request->{data}->{request}->{baz}

      list_path => ['путь','для','сохранения', 'списка'],
      sql => [
        'dbl' # тип БД-сервера

        # запрос к БД с плейсхолдерами
        ,'SELECT id, name, ddate
          FROM test_rmd
          WHERE id = ?
            OR id BETWEEN ? AND :bar
          ORDER BY id DESC'
        # далее идут параметры к запросу,
        # которые подставляются в плэйсхолдеры попорядку
        ,'ref.t1' # первый '?'. т.к. это строка начинающаяся на 'ref.',
                  # машина будет искать значение в params текущего body
        ,{':bar' => 'ref.param2'} # плэйсхолдер :bar - он именной, поэтому его все-равно где ставить
        ,3 # второй '?'
      ],
      t1 => 'ref.data.request.param.foo',
      param2 => 'ref.data.request.baz'
    }
  },
	data => Clone::clone($input_data) # входные данны подключим тут
};





my $Expected = {
  #cache_ttl=>1800,
  путь     =>{
    для=>{
      сохранения=>{
        списка=>[
          {
            ddate=>"2017-02-15 19:06:00",
            id   =>6,
            name =>"system of down"
          },
          {
            ddate=>"2010-01-19 10:06:00",
            id   =>5,
            name =>"chokolate"
          },
          {
            ddate=>"2017-02-15 19:06:00",
            id   =>4,
            name =>"faight"
          },
          {
            ddate=>"2014-02-15 19:06:00",
            id   =>3,
            name =>"roboti"
          },
          {
            ddate=>"2017-01-01 00:00:00",
            id   =>1,
            name =>"name uno"
          }
        ]
      }
    }
  }
};



my $socket = send_to_rmd($request,1);
my $res = get_from_rmd($socket);
is_deeply($res, $Expected, 'request l_sql'); # получение результата


# запрос на выбор из БД h_
$request = {
  body => {
    request => 'h_sql',
    params => {
      sql => ['dbl'
        ,'SELECT key1 AS id, p AS field1, ? AS tag1
          FROM test_rmd_h2
          WHERE key1 IN (:ids)
          ORDER BY field1'
        ,'ref.t1'
      ],
      t1 => 'ref.data.other.data',
      param2 => 'ref.data.other.baz'
    }
  },
  childs => [{
    body => {
      request => 'h_sql',
      params => {
        sql => ['dbl'
          ,'SELECT art AS id, t AS from_h3, ? AS tag1
            FROM test_rmd_h3
            WHERE art = 1
              AND art IN (:ids)
            ORDER BY tag1'
          ,'ref.t2'
        ],
        t2 => 'ref.data.result.list.hash_by_id.1.l_field',
      }
    }
  },{
    body => {
      request => 'h_sql',
      params => {
        sql => ['dbl'
          ,'SELECT art AS id, t AS from_h3, ? AS tag1
            FROM test_rmd_h3
            WHERE art = 4
              AND art IN (:ids)
            ORDER BY tag1'
          ,'ref.t2'
        ],
        t2 => 'ref.data.result.list.hash_by_id.5.field1',
      }
    }
  },{
    body => {
      request => 'h_sql',
      params => {
        sql => ['dbl'
          ,'SELECT art AS id, t AS from_h3, ? AS tag1
            FROM test_rmd_h3
            WHERE art > 5
              AND art IN (:ids)
            ORDER BY tag1'
          ,'ref.t2'
        ],
        t2 => 'ref.data.result.list.hash_by_id.5.field1',
      }
    }
  }],
	data => Clone::clone($input_data) # входные данны подключим тут
};
$request->{data}->{result} = {
  list => {
    hash_by_id => {
      4 => { id => 4, l_field => 'L4', l_f2 => [{l_f3 => 'что-то еще'}] },
      1 => { id => 1, l_field => 'L1 text' },
      5 => { id => 5, l_field => 'L5' },
      99 => { id => 99, l_field => 'L99' },
    },
    ordered_list => [
      { id => 4 },
      { id => 5 },
      { id => 1 },
      { id => 99 },
    ],
    rows => 5,
  }
};

$Expected = {
  #cache_ttl => 1800,
  list => {
    hash_by_id => {
      1 => {
        field1  => 0,
        from_h3 => 111,
        tag1    => 'L1 text'
      },
      4 => {
        from_h3 => 44,
        tag1    => -25
      },
      5 => {
          field1 => -25,
          tag1   => "may be here"
      },
      #99 => {},
    },
    #list_prepared => "list.hash_by_id.%.id"
  },
};


$socket = send_to_rmd($request);
$res = get_from_rmd($socket);
#DDP::p($res);
is_deeply($res, $Expected, 'request h_sql'); # получение результата



# запрос с дочками
$request = {
	data => $input_data, # входные данны подключим тут
  body => {
    request => 'l_sql',
    params => {
      list_path => ['путь_списка'],
      sql => [
        'dbl'
        ,'SELECT id, name
          FROM test_rmd
          ORDER BY id
          LIMIT ?,?'
        ,3,4
      ]
    }
  },
  childs => [
    {
      body => {
        request => 'h_sql',
        params => {
          hash_of_lists => ['результата', 'путь'],
          sql => [
            'dbl'
            # если указать имя поля 'as_id', то в окончательном результате
            # это поле 'as_id' заменит собой 'id'
            # 'as_id' можно делать только при существующем параметре 'list_of_path'
            ,'SELECT key1 AS id, xml_text, p AS as_id
              FROM test_rmd_h2
              WHERE key1 = 6
                AND key1 IN (:ids)'
            # плейсхолдер :ids для обработчика h_ заменяется автоматически
            # на список через запятую, полученый родительским l_
          ]
        }
      }
    },
    {
      body => {
        request => 'h_sql',
        params => {
          sql => [
            'dbl'
            ,'SELECT art AS id, t AS topotam
              FROM test_rmd_h3
              WHERE art != ?
                AND art IN (:ids)',
            'ref.f'
          ],
          f => 4
        }
      }
    }
  ]
};


$Expected = {
  #cache_ttl  =>1800,
  путь_списка=>[
    {
      id  =>4,
      name=>"faight"
    },
    {
      id     =>5,
      name   =>"chokolate",
      topotam=>55
    },
    {
      id        =>6,
      name      =>"system of down",
      topotam   =>66,
      результата=>{
        путь=>[
          {
            id      =>-1,
            xml_text=>'<moon is="chees"/>'
          },
          {
            id      =>0,
            xml_text=>"<b/>"
          },
          {
            id      =>42,
            xml_text=>'<test x="1"/>'
          }
        ]
      }
    },
    {
      id     =>7,
      name   =>"lamp",
      topotam=>77
    }
  ]
};

$socket = send_to_rmd($request);
$res = get_from_rmd($socket);
is_deeply($res, $Expected, 'request l_sql with children h_sql'); # получение результата















sub send_to_rmd {
  my $data = shift;
  my $TestConnect = shift || 0;
	my $socket = new IO::Socket::INET (
    PeerHost => 'localhost',
    PeerPort => '1071',
    Proto => 'tcp',
    Timeout	 => 1
  );
  ok($socket,'connect TCP-socket') if $TestConnect;

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
	eval {
		while (<$socket>) {
			last if ($_ eq "\cD\n");
			push @json, $_;
		}
		$socket->shutdown(2);
	};
	if ($@) {
    warn "[WARN] $@";
		@json = (); # что-то пошло не так
	}
  $json[-1] =~ s/\x04$// if scalar(@json);
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
      warn "[ERR] $@\n=============\n$json_str\n=============\n";
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
