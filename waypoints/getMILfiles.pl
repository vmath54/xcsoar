#!/usr/bin/perl
#
# recuperation de cartes VAC, depuis le site http://www.dircam.air.defense.gouv.fr
# permet de completer les cartes VAC recuperees depuis le site SIA
#
# pour se limiter aux cartes VAC, on va a http://www.dircam.air.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france
#
# exemple d'url finale, pour une carte : http://www.dircam.air.defense.gouv.fr/images/stories/Doc/AVUE/avue_nancy_ochey_lfso.pdf
#                     ou, plus complet : http://www.dircam.air.defense.gouv.fr/images/stories/Doc/MIAC4/miac4_fr_nancyochey_lfso.pdf
#
# on ne recupere pas les cartes qu'on a par ailleurs depuis le site SIA ($dirSIA)

use LWP::Simple;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $dirDownload = "mil";    # le répertoire qui va contenir les documents pdf charges
my $dirSIA = "./vac";            # les fichiers pdf recuperes du site SIA

my $pageURL = "http://www.dircam.air.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france";
my $baseURL = "http://www.dircam.air.defense.gouv.fr/images/stories/Doc/AVUE";  # url de la page de téléchargement des cartes VAC

{
  my $ADsia = &getListSIA($dirSIA);   # les AD qu'on a deja charges depuis le site SIA

  #my $page = get($pageURL);
  my $page; { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT }  # debug
  die "Impossible de charger la page $pageURL" unless (defined($page));
  
  my $ADs = &decodePage($page);
  
  mkdir $dirDownload;
  
  foreach my $ad (sort keys %$ADs)
  {
    #next if ($ad ne "LFSO");
	next if (defined($$ADsia{$ad}));   # on ne traite pas les fichiers deja charges depuis le site SIA
    my $refAD = $$ADs{$ad};
	$ad = lc($ad);
	my $name = $$refAD{name};
	$name =~ s/ /_/sg;
	$name = lc($name);
	my $urlPDF = $baseURL . "/avue_" . $name . "_" . $ad . ".pdf";
	print "$urlPDF\n"; next;
	print "$ad.pdf\n";
	my $status = getstore($urlPDF, "$dirDownload/$ad.pdf");   #download de la fiche pdf
    unless ($status =~ /^2\d\d/)
    {
	  print "code retour http $status lors du chargement du doc $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
	sleep 1;
  }
}

# on memorise les terrains deja recuperes depuis le site SIA
sub getListSIA
{
  my $dir = shift;
  
  my %ADs = ();
  
  my @fics = glob("$dir/*.pdf");
  return () if (scalar(@fics) == 0);
  
  #print Dumper(\@fics); exit;
  foreach my $ad (@fics)
  {
    my ($rep,$fic) = $ad =~ /(.+[\/\\])([^\/\\]+)$/; 
    $fic =~ s/\.pdf$//;
	$ADs{$fic} = 1;
  }
  return \%ADs;
}

#    ------------ decode la page html qui permet de choisir un terrain --------------------
# les infos necessaires se trouvent dans du code javascript :
#
# voici un extrait de la page html (ou plutot, du code javascript) qui permet d'obtenir la liste des cartes de vol a vue disponibles :
#
# <script language='JavaScript' type='text/JavaScript'>
#  var terrain_avue =new Array(
#  "AGEN LA GARENNE","AIRE SUR L'ADOUR","AIX LES MILLES",...,"NANCY OCHEY",...);
#  var indicateur_avue =new Array(
#  "LFBA","LFDA","LFMA","LFKJ","LFAQ",...,"LFSO",...);

sub decodePage
{
  my $page = shift;
  
  my %ADs = ();     # va contenir le code et le nom des terrains disponible
  
  unless ($page =~ /var indicateur_avue =new Array\(\n(.*?)\);/)
  {
    die "pas trouve le contenu de la variable javascript 'indicateur_avue'";
  }

  my $allCodes = $1;   # contient une chaine comme : "LFOI","LFBA","LFDA",...
  $allCodes =~s/^ +?//;
  $allCodes =~ s/"//sg;    # retrait des guillemets
  my @codes = split(",", $allCodes);
  
  unless ($page =~ /var terrain_avue =new Array\(\n(.*?)\);/)
  {
    die "pas trouve le contenu de la variable javascript 'terrain_avue'";
  }

  my $allNames = $1;
  $allNames =~s/^ +?//;
  $allNames =~ s/"//sg;
  my @names = split(",", $allNames);  
  
  for (my $ind = 0 ; $ind < scalar(@codes) ; $ind++)
  {
    my $code = $codes[$ind];
	$ADs{$code}{code} = $code;
	$ADs{$code}{name} = $names[$ind];
	#$ADs{$code}{name} = unac_string($names[$ind]);
  }
  
  return \%ADs;
}
