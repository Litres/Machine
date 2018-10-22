###########################################################################
# base 'XPortal::CachedObject'
###########################################################################


=head1 XPortal::CachedObject::LibHouse

Класс для извлечения и кэширования суммарной статистики по библиотеке. Потомок B<XPortal::CachedObject>.

=cut
package XPortal::CachedObject::LibHouseSettings;
use strict;
use base 'XPortal::CachedObject';

sub Init {
  my $c = shift;
  my $X = $c->{'X'};
  my	$Out = XPortal::General::FetchAsXMLQuery($X, ['lib', {
      AttribFunc => sub {
        my $Out;
        if ($_[0]->[7]) {
          my $Paths = XPortal::Pages::LibHouses::GetLogoPathByFileID( $X->{s}->{Lib}, $_[0]->[6], 'png' );
          $Out = ' logo_path="/' . $Paths->{file_rel_path} . '"';
        }
        return $Out . &XPortal::Pages::MoneyHolder::GetAccountAmountAttrs($X->{s}->{LibFace}, $_[0]->[6], ['','','','account']);
      }
    }], 'dbl', "
    SELECT
      l.show_art_price_parent AS 'watch-price-librarian',
      l.show_art_price_child AS 'watch-price-users',
      l.show_account_parent AS 'watch-account-librarian',
      l.s_name,
      -- GROUP_CONCAT(l.s_name ORDER BY l.id ASC SEPARATOR ', ') AS s_name,
      IF(l.show_email = 1 AND u.mail_confirmed = 1, u.s_mail, NULL) AS s_mail,
      (
        SELECT COUNT(*) AS request
        FROM biblio_parents bp
        JOIN biblio_requests r ON r.reader = bp.child
        WHERE r.verdict IS NULL AND bp.parent = l.id
      ) as request,
      l.id,
      l.logo_width,
      l.libhouse_group,
			l.face as libhouse_face,
			lg.is_school,
      l.art_give_done,
      l.art_give_limit,
			lh.host AS library_base_host,
			lh_pda.host AS library_base_pda_host,
      l.readers_can_reg,
			l.selfservice
    FROM libhouses AS l
      JOIN users AS u ON u.id = l.id
			LEFT JOIN libhouse_group AS lg ON l.libhouse_group = lg.id
			LEFT JOIN fbhub.lib_hosts AS lh ON l.face=lh.lib_face AND lh.xslt='LitRes_new'
			LEFT JOIN fbhub.lib_hosts AS lh_pda ON l.face=lh_pda.lib_face AND lh_pda.xslt IN ('pda_2.0', 'PDA')
    WHERE l.id = ?
		GROUP BY l.id"
    , $X->{u}->{ID}
  );
  $c->{'data'} = $Out;

  return 1;
}

sub Relations{
  return ('LibHouse');
}





###########################################################################
# base 'XPortal::CachedObject::Stamp'
###########################################################################

package XPortal::CachedObject::Stamp::LibHouse;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  return ($Params->{params}->{libhouse} || $X->{u}->{ID}, $X->{s}->{LibFace});
};

package XPortal::CachedObject::Stamp::UserLibHouses;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  my @Libhouses;
  if (defined $X->{u}->{LibHouses}) {
    @Libhouses = @{ $X->{u}->{LibHouses} };
  } else {
    #warn "LH UNDEF U " . $X->{u}->{ID};
  }
  my @RetrunObjs;
  foreach my $Libhouse (@Libhouses) {
    my $X4U = $X->XPortalForUser($Libhouse);
    push(@RetrunObjs, XPortal::CachedObject::Stamp::LibHouse->new({ X => $X4U }) );
  }
  return ($X->{u}->{ID}, $X->{s}->{Lib}, 'Stamp::User', @RetrunObjs);
};

package XPortal::CachedObject::Stamp::LibHousePoster;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  return ($X->{u}->{ID}, $X->{s}->{Lib});
};

package XPortal::CachedObject::Stamp::UserLibHousePosters;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $X = $_[0]->{'X'};
  my @Libhouses;
  if (defined $X->{u}->{LibHouses}) {
    @Libhouses = @{ $X->{u}->{LibHouses} };
  } else {
    #warn "LH UNDEF2 U " . $X->{u}->{ID};
  }
  my @RetrunObjs;
  foreach my $Libhouse (@Libhouses) {
    my $X4U = $X->XPortalForUser($Libhouse);
    push(@RetrunObjs, XPortal::CachedObject::Stamp::LibHousePoster->new({ X => $X4U }) );
  }
  return ($X->{u}->{ID}, $X->{s}->{Lib}, @RetrunObjs);
};

#Читатели библиотеки
package XPortal::CachedObject::Stamp::LibHouseReaders;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  return ($X->{s}->{Lib}, $Params->{params}->{libhouse} || $X->{u}->{ID}, 'Stamp::LibHouse');
}

#Читатели библиотек, к которым относится юзер
package XPortal::CachedObject::Stamp::UserLibHouseReaders;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  my @Libhouses;
  if (defined $X->{u}->{LibHouses}) {
    @Libhouses = @{ $X->{u}->{LibHouses} };
  } else {
    #warn "LH UNDEF3 U " . $X->{u}->{ID};
  }
  my @RetrunObjs;
  foreach my $Libhouse (@Libhouses) {
    my $X4U = $X->XPortalForUser($Libhouse);
    push(@RetrunObjs, XPortal::CachedObject::Stamp::LibHouseReaders->new({ X => $X4U }) );
  }
  return ($X->{u}->{ID}, $X->{s}->{Lib}, @RetrunObjs);
}

#Подборки библиотеки
package XPortal::CachedObject::Stamp::LibHouseIssues;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  return ($X->{s}->{Lib}, $Params->{params}->{libhouse} || $X->{u}->{ID});
}

#Подборки библиотек, к которым относится юзер
package XPortal::CachedObject::Stamp::UserLibHouseIssues;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
  my $Params = shift();
  my $X = $Params->{'X'};
  my @Libhouses;
  if (defined $X->{u}->{LibHouses}) {
    @Libhouses = @{ $X->{u}->{LibHouses} };
  } else {
    #warn "LH UNDEF4 U " . $X->{u}->{ID};
  }
  my @RetrunObjs;
  foreach my $Libhouse (@Libhouses) {
    my $X4U = $X->XPortalForUser($Libhouse);
    push(@RetrunObjs, XPortal::CachedObject::Stamp::LibHouseIssues->new({ X => $X4U }) );
  }
  return ($X->{u}->{ID}, $X->{s}->{Lib}, @RetrunObjs);
}

1;
