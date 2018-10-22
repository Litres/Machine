###########################################################################
# base 'XPortal::CachedObject'
###########################################################################

package XPortal::CachedObject::PaymentsVisible;
use strict;
use base 'XPortal::CachedObject';

sub Relations { return ('PaymentsVisible'); };

sub Init {
  my $c = shift;
  $c->{'data'} = '<payments_visible>'.
		XPortal::General::FetchAsXMLQuery($c->{X},'descr','dbl',
			"SELECT
				descr_id AS id,
				status,
				priority
			FROM payments_visible"
		).'</payments_visible>';
  return $c;
}

###########################################################################
# base 'XPortal::CachedObject::Stamp'
###########################################################################

package XPortal::CachedObject::Stamp::PaymentsVisible;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $X = $_[0]->{'X'};
  return ($X->{s}->{Lib});
}


1;
