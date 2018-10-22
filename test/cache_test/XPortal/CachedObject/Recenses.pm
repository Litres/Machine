###########################################################################
# base 'XPortal::CachedObject'
###########################################################################


###########################################################################
# base 'XPortal::CachedObject::Stamp'
###########################################################################

package XPortal::CachedObject::Stamp::RecensesArt;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $X = shift()->{'X'};
	return ($X->{s}->{Lib}, ($X->single_param('art') || $X->single_param('rel_id')));
}

package XPortal::CachedObject::Stamp::RecensesPerson;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $X = shift()->{'X'};
	return ($X->{s}->{Lib}, ($X->single_param('person') || $X->single_param('rel_id')));
}

#пока используются, только в get_recenses.json
package XPortal::CachedObject::Stamp::RecensesSequence;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $X = shift()->{'X'};
	return ($X->{s}->{Lib}, ($X->single_param('sequence') || $X->single_param('rel_id') || $X->single_param('id')));
}

#пока используются, только в get_recenses.json
package XPortal::CachedObject::Stamp::RecensesCollection;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $X = shift()->{'X'};
	return ($X->{s}->{Lib}, ($X->single_param('collection') || $X->single_param('rel_id')));
}

package XPortal::CachedObject::Stamp::QuoteArt;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $Params = shift();
	my $X = $Params->{'X'};
	my $ArtID = $Params->{params}->{'art'} || $X->single_param('art');
	return ($X->{s}->{Lib}, $ArtID);
}

1;
