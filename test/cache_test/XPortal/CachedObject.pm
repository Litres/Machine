use strict;
use ServerID;
use XPortal::CachedObject::User;
use XPortal::CachedObject::LibHouse;
use XPortal::CachedObject::Recenses;
use XPortal::CachedObject::Reader;
use XPortal::CachedObject::Search;
use XPortal::CachedObject::Payments;

=encoding utf-8
=pod

=head1 CachedObject

Базовый класс для работы с кешируемыми объектами, поддерживает стухание кэша

=head2 Свойства

=over

=item * B<X> - объект XPortal

=item * B<relations> - список названий отпечатков, от которых зависят данные

=item * B<data> - данные, которые мы будем читать/писать в кэш и возвращать

=back

=cut

package XPortal::CachedObject;
use strict;
use XPortal::Memcached;
use Time::HiRes qw/time/;

use constant VERSION => '2.0';
sub new {
  my $class = shift;
  my $p = shift || {}; # params
  Carp::confess("[ERR] X (XPortal) is required!") unless $p->{'X'} && ref($p->{'X'});
  my $c = {
    type => $class,
    X => delete($p->{'X'}),
    cache_ttl => $p->{'cache_ttl'} ? delete($p->{'cache_ttl'}) : 300, # время жизни кэша
    params => $p,
    stamp_objects => $p->{stamp_objects} || {}, # нужен для ::Stamp
  };

  bless $c, $class;

  return $c;
}

=head2 Методы

=head3 Type

Возвращает префикс для ключа кэша. Использует имя класса и версию модуля.

=cut

sub Type{ return join(':', $_[0]->{'type'}, &VERSION); }

=head3 _mkLastTime

Формирует метку последнего изменения данных

=cut
sub _mkLastTime {
  return $_[0]->{'last_modified'} = int(Time::HiRes::time()*1000);
}

=head3 KeyDelimiter

Возвращает раздилитель параметров для ключа кэша.
По умолчанию возвращает '_'. Может быть переопределен в дочерних классах.

=cut
sub KeyDelimiter{ return '_'; }

=head3 LoadData

Загружает данные в B<data>.
Сначала пробует достать из кэша, если там их нет, запускает метод B<Init>

=cut
sub LoadData {
  my $c = shift;

  unless ($c->_InitFromCache()){ #Нет данных в кеше. Получим из базы
    $c->_mkLastTime();
    $c->Init();
    $c->_StoreToCache();
  }
  return $c; # вернем объект обратно
}

=pod

=head3 Init

Метод формирующий данные для кэширования.
Должен быть переопределен в дочерних классах.

=cut

sub Init {
  die "Unimplemented method Init called for ".ref(shift);
}

=head3 GetCacheKey

Генерит составной ключ на основании B<type> и B<отпечатков>, от которых зависят данные

=cut

sub GetCacheKey {
  my $c = shift;
  unless ($c->{'cachekey'}){
    # нужно сформировать ключ для нашего объекта
    # а для этого нужны отпечатки всех объектов, от которых зависит наш
    my @Stamps;
    for my $stamp ($c->GetObjForRels()){ # объект
      #print "!!!!!!!!!!!!!! ".$stamp->GetCacheKey(),"\n";
      $stamp->LoadData();
      # сам отпечаток лежит в $stamp->{'data'}
      # но нам надо бы еще время последнего изменения посмотреть
      $c->{'last_modified'} = $stamp->{'last_modified'}
        if ($c->{'last_modified'} < $stamp->{'last_modified'});
      push(@Stamps, $stamp->{'data'});
    }
    # теперь на основе всех отпечатков сформируем наш ключ для объекта
    $c->{'cachekey'} = join($c->KeyDelimiter(), $c->Type(), @Stamps);
  }
  return $c->{'cachekey'};
}

=head3 GetLastModified

Достает время последнего издменения данных

=cut

sub GetLastModified{
  my $c = shift;
  unless ($c->{'last_modified'} || $c->_InitFromCache()){
    # если в кэше ничего нет, значит время последнего изменения будет сейчас
    $c->_mkLastTime();
  }
  return $c->{'last_modified'};
}

=pod

=head3 _InitFromCache

Получает данные из кеша с ключом GetCacheKey(). Приватный метод
=cut

sub _InitFromCache {
  my $c = shift;
  my ($SessionData, $from_cache);
  if ($c->{X} && exists($c->{X}->{s})){
    $SessionData = $c->{X}->{s}->{CachedObjects} ||= {};
  }
  $from_cache = $SessionData->{$c->GetCacheKey()} if $SessionData;
  #print STDERR "[$$] !!== ",ref($c),"\n";
  unless ($from_cache){
    #print STDERR "[$$] ==== ",ref($c),"\n";
    $from_cache = XPortal::Memcached::ReadCache($c->GetCacheKey());
    $SessionData->{$c->GetCacheKey()} = $from_cache if $from_cache;
  }
  if ($from_cache) {
    $c->{'data'} = $from_cache->{'data'};
    $c->{'last_modified'} = $from_cache->{'last_modified'};
    return 1;
  }
  return;
}

=pod

=head3 GetObjForRels

Метод создает список из объектов отпечатков, от которых зависят данные.

=cut

sub GetObjForRels {
  my $c = shift;
  unless ($c->{'relations'}){
    my @Rels = $c->Relations();
    Carp::confess("[ERR] cannot get Relations!") unless @Rels;
    $c->{'relations'} = [];
    for my $rel (sort @Rels){
      # сделаем класс для этой связи
      my $class = 'XPortal::CachedObject::Stamp::'.$rel;
      #require $class;
      my %params=%{$c->{params}};
      delete $params{relations};

      push(@{ $c->{'relations'} },
        $class->new({
          %params,
          X => $c->{'X'},
          type => $class
        })
      );
    }
  }
  return @{ $c->{'relations'} };
}

=pod

=head3 Relations

Метод, который должен быть переопределен в дочерних классах.
Должен вернуть список с названиями отпечатков, от которых зависят данные.

=cut
sub Relations{
  die "Unimplemented method Init called for ".ref(shift);
}

=pod

=head3 Invalidate

Метод, который экспайрит кеш объекта (по ключу GetCacheKey())

=cut

sub Invalidate {
  my $c = shift;
  #warn "[OK] Invalidate: ".$_[0]->GetCacheKey();
  $c->{X}->{s}->{CachedObjects}->{$c->GetCacheKey()} = ''
    if exists($c->{X})
      && exists($c->{X}->{s})
      && exists($c->{X}->{s}->{CachedObjects})
      && exists($c->{X}->{s}->{CachedObjects}->{$c->GetCacheKey()});
  XPortal::Memcached::DeleteCache($c->GetCacheKey());
}

=pod

=head3 _StoreToCache

Кладет в кеш данные с ключом GetCacheKey(). Если по этому ключу уже что-то есть, то он их перезаписывает.

=cut

sub _StoreToCache {
  my $c = shift;
  my $data = {
    data => $c->{'data'},
    last_modified => $c->_mkLastTime(),
  };
  if ($c->{X} && exists($c->{X}->{s})){
    $c->{X}->{s}->{CachedObjects} ||= {};
    $c->{X}->{s}->{CachedObjects}->{$c->GetCacheKey()} = $data;
  }
  XPortal::Memcached::WriteCache($c->GetCacheKey(), $data,$c->{'cache_ttl'});
}

=pod

=head3 SetStampTTL

Проверяет $RelName в Relations и при наличии такого устанавливает этому отпечатку время жизни в memcached равное $TTL

=cut

sub SetStampTTL {
  my $c = shift;
  my $RelName = shift;
  my $TTL = shift;
  my $i=0;
  my @Rels = $c->Relations();
  for my $rel (sort @Rels) { #тот же sort юзается в GetObjForRels, надо чтобы порядок там и там был одинаков
    if ($rel eq $RelName ) {
      my $s;
      $s = $c->{'relations'}->[$i] if (exists($c->{'relations'}->[$i])); # это кэш уже созданных объектов
      unless ($s){
        my $class = 'XPortal::CachedObject::Stamp::'.$rel;
        my %params=%{$c->{params}};
        delete $params{relations};
        $s = $class->new({
          %params,
          X => $c->{'X'},
          type => $class,
          cache_ttl => $TTL,
        });
      }
      $s->{cache_ttl} = $TTL;
      $s->_StoreToCache();
      return; # $RelName только один же
    }
    $i++;
  }
}

#=head1 CachedUserHash
#
#Класс-потомок B<CachedObject>. Базовый класс для кеширования данных пользователя.
#
#=head2 Свойства
#
#=over
#
#=item * B<lib> - идентификатор либы
#
#=item * B<id> - идентификатор пользователя в либе
#
#=back
#
#=cut
#
#package CachedUserHash;
#use vars qw(@ISA);
#use strict;
#
#@ISA = qw(CachedObject);
#
#=head2 Параметры конструктора
#=over
#
#=item * B<lib> - идентификатор либы
#
#=item * B<id> - идентификатор пользователя
#
#=back
#=cut
#
#sub Init {
#  my $self = shift;
#
#  my $data = {'lib' => $self->{'params'}->{'lib'}};
#
#  XPortal::DB::ConnectLocal(undef, $data->{'lib'} == 1 ? 'fbhub' : 'lib_area_'.$data->{'lib'}) if defined($data->{'lib'});
#
#  ($data->{'id'}, $data->{'username'}, $data->{'last_paymethod'}) = XPortal::DB::DBQuery('dbl',
#   'SELECT
#      u.id,
#      u.login,
#      u.last_paymethod
#    FROM users u
#    WHERE u.id = ?
#  ', $self->{'params'}->{'id'})->fetchrow();
#
#  return unless $data->{'id'};
#
#  $data->{'groups'} = [
#    map {$_->[0]} @{
#      XPortal::DB::DBQuery('dbl',
#        'SELECT group_id FROM groupusers  WHERE user_id = ?',
#        $self->{'params'}->{'id'})->fetchall_arrayref()
#  }];
#
#  $data->{'accounts'} = XPortal::User::LoadUserAccounts($data->{'id'});
#
#  $self->{'data'} = $data;
#
#  return 1;
#}


=head1 XPortal::CachedObject::Stamp

Базовый класс для отпечатков. Потомок B<XPortal::CachedObject>.

=cut
package XPortal::CachedObject::Stamp;
use strict;
use base 'XPortal::CachedObject';

sub KeyDelimiter{ return ':'; }
sub GetCacheKey {
  my $s = shift;
  unless ($s->{'cachekey'}){
    my @Rels;
    for my $rel ($s->Relations()){
      if (index(ref($rel),'XPortal::CachedObject::Stamp') == 0) {
        # если передан готовый объект отпечатка
        $rel->LoadData();
        Carp::confess("[ERR] can't load data for object ".ref($rel)) unless $rel->{data};
        push (@Rels,$rel->{data});
      } elsif (index($rel,'Stamp::') == 0) {
        # ого! это зависимость от другого отпечатка
        if (exists($s->{params}->{double_detector}) && exists($s->{params}->{double_detector}->{$rel})) {
          Carp::confess("[ERR] infinity recourse detected: '$rel'");
        }
        my $stamp;
        if (exists( $s->{stamp_objects}->{$rel} )){
          $stamp = $s->{stamp_objects}->{$rel};
        } else {
          my $class = 'XPortal::CachedObject::'.$rel;
          $stamp = $s->{stamp_objects}->{$rel} = $class->new({
            %{$s->{params}},#[95523] На случай передачи параметров
            X => $s->{'X'},
            double_detector => $s->{params}->{double_detector} || {$rel => 1},
            stamp_objects => $s->{stamp_objects}, # уже созданные отпечатки
          });
          $stamp->LoadData();
          Carp::confess("[ERR] stamp not found '$rel'") unless $stamp->{data};
        }
        push (@Rels,$stamp->{data});
      } else {
        # обычные данные, от которых зависит отпечаток ($X->{u}->{ID}, $X->{u}->{Lib}, и т.п.)
        push (@Rels,$rel);
      }
    }
    $s->{'cachekey'} = join($s->KeyDelimiter(), $s->Type(), @Rels);
  }
  return $s->{'cachekey'};
}

sub Init { shift->_Init(); }

sub _Init {
  my $s = shift;
  $s->{'data'} = join(':', $s->{'last_modified'}, $$, int(rand(1000)), $ServerID::ID);
  #warn "[OK] $c->{'last_modified'} : ".$c->GetCacheKey(); sleep 1;
  return 1;
}
sub GetObjForRels{ Carp::confess("[ERR] method 'GetObjForRels' not allowed"); }




=head1 XPortal::CachedObject::ChkStampTime

Класс-потомок B<XPortal::CachedObject>, который сам данные не формирует
и не хранит, но позволяет посмотреть время последнего изменения зависимых отпечатков.

=head2 Свойства

=over

=item * B<relations> - список названий зависимых отпечатков

=back

=cut
package XPortal::CachedObject::ChkStampTime;
use base 'XPortal::CachedObject';

sub Relations { return @{ shift()->{'params'}->{'relations'} }; };
sub Type{
  my $c = shift;
  return join(':',$c->{'type'},&XPortal::CachedObject::VERSION, sort $c->Relations());
}
sub GetLastModified{
  my $c = shift;
  $c->GetCacheKey() unless ($c->{'last_modified'});
  return $c->{'last_modified'};
}

sub NotAllowed { Carp::confess("[ERR] method '".(caller(1))[3]."' not allowed"); }
sub LoadData { $_[0]->NotAllowed() }
sub _InitFromCache { $_[0]->NotAllowed() }
sub Init { $_[0]->NotAllowed() }
sub _StoreToCache { $_[0]->NotAllowed() }


1;
