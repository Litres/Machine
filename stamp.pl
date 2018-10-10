use strict;
use utf8;

use JSON::XS;
use XPortal::CachedObject;

my $JSON = JSON::XS->new->allow_nonref->allow_blessed->utf8(1);

sub cache_key {
    my $input = shift;
    my $d = $JSON->decode($input);

    return unless $d->{body}->{cache_rels};

    # Если в cache_rel указан отпечаток, со списоком парамаметров. Переносим из из body: rel_id
    # cache_rels => [{'UserFollowers'=>['rel_id']}]
    my $Params = {};
    my $CacheRelsNames = [];
    for (@{$d->{body}->{cache_rels}}) {
        if (ref($_) eq 'HASH') {
            my $Name = (keys (%{$_}))[0];
            foreach my $ParamFromBody (@{$_->{$Name}}) {
                if (not defined $d->{body}->{params}->{$ParamFromBody}) {
                    $d->fatal("Cache_rels param not found");
                    return;
                }
                $Params->{$ParamFromBody} = $d->{body}->{params}->{$ParamFromBody};
            }
            push (@$CacheRelsNames, $Name);
        } else {
            push (@$CacheRelsNames, $_);
        }
    }

    # создадим объект, которые ничего не достает и не сохраняет в мемкеш,
    # но чекает зависимые отпечатки
    $d->{data}->{user}->{ID} = $d->{data}->{user}->{id};

    my $ChkStamps = new XPortal::CachedObject::ChkStampTime({
        %{$Params},
        X => { 
            # там нужно окружение
            s => $d->{data}->{request},
            u => $d->{data}->{user},
        },
        relations => $CacheRelsNames
    });

    return $ChkStamps->GetCacheKey();
}
