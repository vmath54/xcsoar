#!/usr/bin/perl
#
# recuperation de cartes VAC militaires
#
# plus possible de recuperer de manière automatique ; on procede manuellement.
#
# Voir la page https://www.dircam.dsae.defense.gouv.fr/fr/documentation-4/a-vue
#
# on part d'une liste d'AD predefinie
#
# exemple d'URL finale pour une carte : https://www.dircam.dsae.defense.gouv.fr/images/Stories/Doc/AVUE/avue_nancy_ochey_lfso.pdf
#
# A noter qu'il faut présenter au site www.dircam.dsae.defense.gouv.fr un User-Agent "propre", et gérer les cookies, sous peine de se faire black-lister plusieurs jours
# Ce script se charge de cela
#

use lib ".";       # necessaire avec strawberry, pour VAC.pm
use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $dirDownload = "mil";    # le répertoire qui va contenir les documents pdf charges

my $baseURL = "https://www.dircam.dsae.defense.gouv.fr/images/Stories/Doc/AVUE/";  # url de la page de téléchargement des cartes VAC


my %ADs = 		# liste des ADs militaires
(
  lfbc => "cazaux",
  lfbm => "montdemarsan",
  lfks => "solenzara",
  lfmo => "orange_caritat",
  lfoa => "avord",
  lfoe => "evreux_fauville",
  lfpv => "villacoublay_velizy",
  lfqe => "etain_rouvres",
  lfqp => "phalsbourg_bourscheid",
  lfsi => "saintdizier_robinson",
  lfso => "nancy_ochey",
  lfsx => "luxeuil_saint_sauveur",
  lfxq => "coetquidan"
);

{
    mkdir $dirDownload;

  foreach my $ad (sort keys %ADs)
  {
    #next if ($ad ne "lfso");
	my $urlPDF = $baseURL . "/avue_" . $ADs{$ad} . "_" . $ad . ".pdf";
	my $ad2 = uc($ad);
	print "$ad2.pdf\n";

    my ($code, $pdf, $cookies) = &sendHttpRequest($urlPDF);
	unless ($code =~ /^2\d\d/)
    {
	  print "code retour http $code lors du chargement de $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
	&writeBinFile("$dirDownload/$ad2.pdf", $pdf);
	
	sleep 1;
  }
}
