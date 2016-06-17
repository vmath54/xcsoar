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
#
# A noter qu'il faut présenter au site www.dircam.air.defense.gouv.fr un User-Agent "propre", et gérer les cookies, sous peine de se faire black-lister plusieurs jours
#

#use LWP::Simple;
use LWP::UserAgent;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $dirDownload = "mil";    # le répertoire qui va contenir les documents pdf charges
my $dirSIA = "./vac";            # les fichiers pdf recuperes du site SIA

my $pageURL = "http://www.dircam.air.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france";
my $baseURL = "http://www.dircam.air.defense.gouv.fr/images/stories/Doc/AVUE";  # url de la page de téléchargement des cartes VAC

my $UserAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64; rv:47.0) Gecko/20100101 Firefox/47.0";

{
  my $ADsia = &getListSIA($dirSIA);   # les AD qu'on a deja charges depuis le site SIA

  #my $page = get($pageURL);
  my ($page, $cookies) = &sendHttpRequest($pageURL, "GET");

  { local(*OUTPUT, $/); open (OUTPUT, ">page.html") || die "can't open page.html"; print OUTPUT $page; close OUTPUT };  # debug, pour ecrire la page en local
  #my $page; { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT };  # debug, pour lire un fichier html local
  die "Impossible de charger la page $pageURL" unless (defined($page));
  #print "$page\n"; exit;
  
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
	#print "$urlPDF\n"; next;
	print "$ad.pdf\n";

#	my $status = getstore($urlPDF, "$dirDownload/$ad.pdf");   #download de la fiche pdf
#    unless ($status =~ /^2\d\d/)
#    {
#	  print "code retour http $status lors du chargement du doc $urlPDF\n";
#	  print "Arret du traitement\n";
#	  exit 1;
#	}

    my ($pdf, $cookies) = &sendHttpRequest($urlPDF, "GET", COOKIES => $cookies);
	&writeFicBin("$dirDownload/$ad.pdf", $pdf);
	
	sleep 1;
  }
}

sub writeFicBin
{
  my $path = shift;
  my $content = shift;
  
  local(*OUTPUT, $/); 
  open (OUTPUT, '>:raw', $path) || die "can't open $path";
  print OUTPUT $content; 
  close OUTPUT;
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
	$code =~ s/^ //;
	
	#next if($code ne "LFOE");
	
	$ADs{$code}{code} = $code;
	my $name = $names[$ind];
	$name =~ s/^ //;
	$name = unac_string("UTF-8", $name);

	$ADs{$code}{name} = $name;
  }
  return \%ADs;
}

#############################################################################################
#          genration d'une requete http
#Cette fonction permet de gerer les cookies et le User-Agent (entre autres)
# on peut empecher les redirection, avec max_redirect => 0
#############################################################################################
sub sendHttpRequest
{
  my $url = shift;
  my $proto = shift;
  
  my %args = (FORM => "GET", CONTENT_TYPE => "text/html", COOKIES => {}, @_);  
  my $content = $args{CONTENT};
  my $cookies = $args{COOKIES};
  my $contentType = $args{CONTENT_TYPE};

  my $req = new HTTP::Request($proto => $url);  
  $req->content_type($contentType);
  $req->content($content) if (defined($content));
  my $browser = new LWP::UserAgent(keep_alive => 0, timeout => 10, max_redirect => 5);
  $browser->cookie_jar($cookies);
  $browser->agent($UserAgent);
  my $res = $browser->request($req);
  die "Erreur inconnue lors de l'acces a $url" unless(defined($res));
  my $content = $res->content;
  chomp($content);
  my $headers = $res->headers;
  my $codeHTTP = $res->status_line;
  unless ($res->is_success)
  {
    print "$content\n\n";
    print "### Erreur http $codeHTTP lors de l'acces a $url ###\n";
    exit 1;
  }
  return ($content, $browser->cookie_jar);
}
