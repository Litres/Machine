###########################################################################
# base 'XPortal::CachedObject'
###########################################################################


###########################################################################
# base 'XPortal::CachedObject::Stamp'
###########################################################################

package XPortal::CachedObject::Stamp::ReaderQuotes;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $Params = shift();
	my $X = $Params->{'X'};
	my $Reader = $Params->{'params'}->{'reader'} || $X->single_param('reader');
	return ($X->{s}->{Lib}, $Reader);
}

package XPortal::CachedObject::Stamp::ReaderRecenses;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $Params = shift();
	my $X = $Params->{'X'};
	my $Reader = $Params->{'params'}->{'reader'} || $X->single_param('reader');
	return ($X->{s}->{Lib}, $Reader);
}

package XPortal::CachedObject::Stamp::ArtFiles;
use base 'XPortal::CachedObject::Stamp';

sub Relations {
	my $Params = shift();
	my $ArtID = $Params->{params}->{'art'} || $Params->{'X'}->single_param('art');
	return ($ArtID);
}


1;
