###########################################################################
# base 'XPortal::CachedObject'
###########################################################################

package XPortal::CachedObject::UserAccounts;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserAccounts'); }; # XPortal::CachedObject::Stamp::UserAccounts

sub Init {
  my $c = shift;
  $c->{'data'} = XPortal::User::LoadUserAccounts($c->{X}->{u}->{ID});
  return $c;
}

package XPortal::CachedObject::UserDiscounts;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserDiscounts'); };

sub Init {
  my $c = shift;
  my ($data, $TTL)= XPortal::User::LoadPriceDiscount($c->{X}, $c->{X}->{u}->{ID});
  $c->{'data'}=$data;
  $c->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);#Кешируется до окончания первой цены
  $c->SetStampTTL('UserDiscounts',$TTL);

  return $c;
}

package XPortal::CachedObject::UserOffersWeb;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserOffers'); };

sub Init {
  my $c = shift;
  my ($data, $TTL) = XPortal::Pages::OfferManager::GetActiveOffersForUser($c->{X}, $c->{X}->{u}->{ID},0);
  $c->{'data'}=$data;
  $c->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);#Кешируется до окончания первого офера
  return $c;
}

package XPortal::CachedObject::UserOffersManage;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserOffers'); };

sub Init {
  my $c = shift;
  my ($data, $TTL) = XPortal::Pages::OfferManager::GetActiveOffersForUser($c->{X}, $c->{X}->{u}->{ID},2);
  $c->{'data'}=$data;
  $c->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);
  return $c;
}

package XPortal::CachedObject::UserOffersCat;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserOffers'); };

sub Init {
  my $c = shift;
  my ($data, $TTL) = XPortal::Pages::OfferManager::GetActiveOffersForUser($c->{X}, $c->{X}->{u}->{ID},1);
  $c->{'data'}=$data;
  $c->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);
  return $c;
}

package XPortal::CachedObject::UserOffersCatBrow;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserOffers'); };

sub Init {
  my $c = shift;
  my ($data, $TTL) = XPortal::Pages::OfferManager::GetCatalitBrowserOffersForUser($c->{X}, $c->{X}->{u}->{ID});
  $c->{'data'}=$data;
  $c->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);
  return $c;
}

package XPortal::CachedObject::BasketCounters;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('BasketCounters'); };

sub Init {
  my $c = shift;
  $c->{'data'} = XPortal::Pages::Basket::LoadCounters($c->{X}->{u}->{ID});
  #$c->{'data'} = '<basket_counters cnt_basket="1" cnt_deferred="1" cnt_purchased="1" id="235769982"/>';
  return $c;
}

package XPortal::CachedObject::BasketInfo;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('Basket','Purchase','LastViews'); };

sub Init {
  my $c = shift;
  $c->{'data'} = XPortal::Pages::Basket::LoadBasketInfo($c->{X}->{u}->{ID});
  return $c;
}


package XPortal::CachedObject::UserOAuthScope;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserOAuthScope'); };

sub Init {
  my $c = shift;
  my $data={};
  my $Sth = XPortal::DB::DBQuery('dbl',
    "SELECT
      s.s_name
    FROM service_oauth_scopes_confirm AS sc
      JOIN service_oauth_token        AS t ON t.id=sc.oauth_token
        JOIN service_oauth_scopes     AS s ON s.id=sc.scope
    WHERE
      t.oauth_app = ?
      AND t.user = ?
      AND t.token_type = 'access'
      AND ( t.expired is NULL
        OR t.expired < NOW() )"
    ,$c->{params}->{client_id}
    ,$c->{X}->{u}->{ID}
  );
  while ( my ($Scope) = $Sth->fetchrow()) {
    $data->{$Scope}=1;
  }

  $c->{'data'} = $data;
  return $c;
}


package XPortal::CachedObject::UserServiceSubscr;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserServiceSubscr'); };

sub Init {
  my $c = shift;
  my $data=[];
  my $Sth = XPortal::DB::DBQuery('dbl',
     " SELECT
        service_subscr, IF(MAX(valid_till) > NOW(), 1,0) AS active, UNIX_TIMESTAMP(MAX(valid_till))
      FROM service_subscriptions_users
      WHERE
        user = ?
      GROUP BY user, service_subscr ASC
    ",$c->{X}->{u}->{ID}
  );

  while(my ($SubscrID, $State, $ValidTill) = $Sth->fetchrow()) {
    push @{$data}, {id=>$SubscrID, active=>$State, valid_till=>$ValidTill};
  }

  $c->{'data'} = $data;
  return $c;
}

package XPortal::CachedObject::UserData;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserData'); };

sub Init {
  my $c = shift;
  my $X = $c->{X};
  my $SID = $c->{params}->{SID} || $X->{u}->{SID};
  if ($SID) {
    $c->{'data'} = XPortal::DB::DBQuery('dbl',
				"SELECT
					sessions.user,
					users.login,
					count(distinct redaersg.id),
					FLOOR((TO_DAYS(NOW())-TO_DAYS(rud.birthday))/365),
					mail_confirmed,
					s_mail,
					users.s_full_name,
					users.offert_accepted,
					m.msisdn AS phone,
					users.partner,
					sessions.is_short,
					group_concat(distinct allgrp.group_id) as all_groups,
					users.last_paymethod,
					users.partner_pin,
					rud.userpic_ext,
					m.tcountry AS tcountry,
					users.uilang AS uilang,
					tl.tag2 AS w_uilang
				FROM sessions
					LEFT JOIN users
						ON users.id=sessions.user
					LEFT JOIN groupusers AS allgrp ON allgrp.user_id=users.id
					LEFT JOIN groups AS redaersg ON redaersg.id = allgrp.group_id AND redaersg.is_reader = 1
					LEFT JOIN registered_user_data as rud
						on users.id = rud.user
          LEFT JOIN msisdns AS m ON m.user_id=users.id
          LEFT JOIN fbhub.tr_languages tl ON tl.id = users.uilang
				WHERE
					sessions.sessid=?
					AND (sessions.ip=? OR sessions.ip='0.0.0.0' OR ?=0)
					AND (sessions.is_short=0 or sessions.last_used>=now() - interval ? minute)
				group by sessions.user",
				$SID,
				$X->{s}->{IP},
				$X->{s}->{CurHostSetup}->{'check_ip'},
				$XPortal::Settings::SessionTTL
			)->fetchall_arrayref()->[0] || [];
  } else {
    $c->{'data'} = [];
  }
  return $c;
}

package XPortal::CachedObject::UserBySID;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('UserBySID'); };

sub Init {
  my $c = shift;
  my $X = $c->{X};
  my $SID = $c->{params}->{SID} || $X->{u}->{SID};
  if ($SID) {
    $c->{'data'} = XPortal::DB::DBQuery('dbl',
				"SELECT	user FROM sessions WHERE sessid = ?",
				$SID,
			)->fetchrow() || 0;
  } else {
    $c->{'data'} = 0;
  }
  return $c;
}

###########################################################################
# base 'XPortal::CachedObject::Stamp'
###########################################################################



=head2 XPortal::CachedObject::Stamp::User

Класс-потомок B<XPortal::CachedObject::Stamp>.

=head2 Свойства

=over

=item * B<X> - объект XPortal. Обязательно должен содержать $X->{u}->{ID}, $X->{s}->{Lib}

=back

=cut
package XPortal::CachedObject::Stamp::User;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = shift()->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{Lib});
};

package XPortal::CachedObject::Stamp::UserAccounts;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{LibFace},'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserDiscounts;
use base 'XPortal::CachedObject::Stamp';

sub Init {
  my $s = shift;
  $s->_Init();
  my $TTL;
  my $XU = $s->{X}->{u};
  if (exists($XU->{PriceDiscountTTL})){
    $TTL = $XU->{PriceDiscountTTL};
  } elsif ($XU->{ID}) {
    (undef, $TTL) = XPortal::User::LoadPriceDiscount($s->{X}, $XU->{ID});
  }
  $s->{'cache_ttl'}=($TTL && $TTL < $XPortal::Settings::SessionTTL*60 ? $TTL : $XPortal::Settings::SessionTTL*60);#Кешируется до окончания первой цены
  return $s;
}
sub Invalidate {
  my $s = shift;
  delete $s->{X}->{u}->{PriceDiscountTTL};
  $s->SUPER::Invalidate();
  $s->{X}->{u}->{PriceDiscount} = XPortal::CachedObject::UserDiscounts->new({ X => $s->{X} })->LoadData()->{data};
}
sub Relations {
  my $X = shift()->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{Lib},'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserRebills;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::Basket;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  return ($X->{u}->{ID} || $X->{u}->{SID}, $X->{s}->{Lib},'Stamp::User');
};

package XPortal::CachedObject::Stamp::Purchase;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{Lib},'Stamp::User');
};

package XPortal::CachedObject::Stamp::LastViews;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  return ('Stamp::User');
};

package XPortal::CachedObject::Stamp::UserOffers;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{Lib},'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserPromoPrice;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return (
    $X->{u}->{ID}, $X->{s}->{LibFace},
    'Stamp::Basket',
    'Stamp::UserDiscounts',
    'Stamp::UserOffers',
  );
};

package XPortal::CachedObject::Stamp::BasketCounters;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return (
    $X->{u}->{ID}, $X->{s}->{Lib},
    'Stamp::Basket',
    'Stamp::Purchase',
  );
};

package XPortal::CachedObject::Stamp::UserWebPush;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::UserTickets;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::UserSlonGifts;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserPushList;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::UserMessages;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::Banners;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::UserFolders;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User' );
};

package XPortal::CachedObject::Stamp::UserChannels;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User' );
};

package XPortal::CachedObject::Stamp::UserRecensesVotes;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserBonuses;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserQuotes;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

#Кто подписан на пользователя
package XPortal::CachedObject::Stamp::UserFollowers;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  return ($X->{s}->{Lib}, $Params->{params}->{rel_id} || $X->{u}->{ID});
}

#На кого подписан пользователь
package XPortal::CachedObject::Stamp::UserFollow;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  return ($X->{s}->{Lib}, $Params->{params}->{rel_id} || $X->{u}->{ID});
}

package XPortal::CachedObject::Stamp::UserSocNet;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::FileUploads;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User', 'Stamp::FileUploadsAllLib' );
};

package XPortal::CachedObject::Stamp::FileUploadsAllLib;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::Subscriptions;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserAudioNotes;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserPDFNotes;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserOAuthScope;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $Params = shift();
	my $X = $Params->{'X'};
	my $ClientID = $Params->{params}->{'client_id'} || $X->single_param('client_id');
	return ($ClientID, 'Stamp::User');
}

package XPortal::CachedObject::Stamp::UserLoyaltyCards;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};


package XPortal::CachedObject::Stamp::UserMsisdns;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserServiceSubscr;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib} );
};

package XPortal::CachedObject::Stamp::SubscriptionsToItems;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $X = shift()->{'X'};
  return ( $X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User');
};

package XPortal::CachedObject::Stamp::UserData;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $s = shift;
  my $X = $s->{'X'};
  return $X->{s}->{CurHostSetup}->{'check_ip'} ? ( $X->{s}->{IP}, 'Stamp::UserBySID' ) : ( 'Stamp::UserBySID' );
};

package XPortal::CachedObject::Stamp::UserBySID;
use base 'XPortal::CachedObject::Stamp';
sub Relations {
  my $s = shift;
  my $X = $s->{'X'};
  return ( $s->{params}->{SID} || $X->{u}->{SID}, $X->{s}->{Lib} );
};

1;
