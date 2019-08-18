package VAC;
#

# Variables et procedures perl en lien avec la mise a disposition de cartes VAC et baseULM
#
# site intéressant pour conversions données GPS :
#     https://www.lecampingsauvage.fr/gps-convertisseur
# et pour générer un fichier kmz : Airspace Converter (appli windows)
#     http://www.alus.it/AirspaceConverter/

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
@ISA = ('Exporter');
@EXPORT = qw( &getPDFsource &getDepartements &readRefenceCupFile &writeRefenceCupFile &buildLineReferenceCupFile &readInfosADs &compareNames &convertGPStoCUP &convertCUPtoDec &convertGPStoDec &sendHttpRequest &writeBinFile);

use LWP::Simple;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;


our $UserAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64; rv:47.0) Gecko/20100101 Firefox/47.0";

# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
# reponse de Michel Hirmke, BASULM, pour LF0221 et LF5763 :
#    Pour Langatte, il y a bien deux terrains appartenant au même propriétaire, avec deux arrêtés distincts, un pour les paramoteurs, l'autre pour les autres classes.
#    Pour Corbeny, il s'agit de deux terrains très proches, mais distincts. L'un est à l'usage exclusif de son propriétaire et de ses invités, l'autre a été créé récemment pour une école.
our $noADs =
{
  "LF0221" => { name => "Azur Ulm",             comment => "doublon avec LF0256, Corbeny" },
  "LF0926" => { name => "Cerizols",             comment => "piste reservee ballons" },
  "LF3733" => { name => "Hippolytaine",			comment => "doublon avec LF3755, St Hippolyte" },
  "LF3952" => { name => "Vauxy - Arbois",       comment => "doublon avec LF3956, Arbois-Ulm" },
  "LF5763" => { name => "Langatte paramoteur",  comment => "meme site que LF5762, Langatte ULM" },
  "LFRJ"   => { name => "LANDIVISIAU",          comment => "Transit VFR" },
  "LFRL"   => { name => "LANVEOC POULMIC",      comment => "Transit VFR" },
  "LFTL"   => { name => "Cannes Quai du large", comment => "helistation" },
};

####################################################################################################
#  lecture du fichier .cup de reference
# Ce fichier est formaté specifiquement comme suit :
#
# <code> <shortName>,<code>,FR,<latitude>,<longitude>,<elevation>,<categorie>,<qfu>,<dimension>,<frequence>,<comment>
#
#  . categorie : 1 pour eau. 2 pour herbe. 3 pour neige. 5 pour dur
#  . elevation : en metres
#  . qfu : direction du terrain
#  . dimension : dimension du terrain
#  . comment est formate :
#        <code> <name> (<departement>). <infos complementaires>
#               infos complementaires commence par "AD " pour un terrain issu du site SIA, "AD-MIL " pour un terrain militaire, "BASULM " pour un terrain basulm
#
# Le 1er parametre peut être un handle de fichier (ex : \*STDIN), ou un nom de fichier 
#
#  parametres formels facultatifs :
#     . onlyAD. Si valué, ne traite que ce terrain
#
# retourne un hash indexe par code de terrain
####################################################################################################

sub readRefenceCupFile
{
  my $fic = shift;
  my %args = (@_);
  
  my $onlyAD = $args{onlyAD};
  
  my %ADs;  
  my $handle;       # handle du fichier a lire
  if (ref $fic)     #le parmaetre passe n'est pas le nom d'un fichier ; c'est donc un handle de fichier
  {
    $handle = $fic;
  }
  else
  {
    die "unable to read fic $fic" unless (open ($handle, "<$fic"));
  }

  while (my $line = <$handle>)
  {
	chomp ($line);
	next if ($line eq "");
	my ($shortName, $code, $country, $lat, $long, $elevation, $nature, $qfu, $dimension, $frequence, $comment) = split(",", $line);
	next if (($onlyAD ne "") && ($code ne $onlyAD));
	$code =~ s/\"//sg;   # on elimine les quotes du code terrain
    die "$line\n   ERREUR. Le code terrain n'est pas conforme" if (($code !~ /^LF\S\S$/) && ($code !~ /^LF\d\d\d\d$/) &&
	               ($code !~ /^LF2[AB]\d\d$/) && ($code !~ /^LF97\d\d\d$/));
	die "$line\n   ERREUR. Le premier champ doit commncer par le code terrain" unless ($shortName =~ s/^\"$code (.*)\"$/\1/);
	die "$line\n   ERREUR. L'altitude doit se terminer par 'm'" if ($elevation !~ s/m$//);
	die "$line\n   ERREUR. La dimension doit se terminer par 'm'" if (($dimension ne "") && ($dimension !~ s/m$//));
	die "$line\n   ERREUR. Le champ 'nature' doit avoir une des valeurs : 1, 2, 3 ou 5" 
	          if (($nature != 1) && ($nature != 2) && ($nature != 3) && ($nature != 5)); 
	die "$line\n   ERREUR. Le dernier champ doit commencer par le code terrain" unless ($comment =~ s/^\"$code \- //);
	die "$line\n   ERREUR. Le dernier champ doit contenir le nom, le departement et un commentaire" 
	  if (($comment !~ s/(.*?) \((\d\d)\)\. (.*)\"$/\3/) && ($comment !~ s/(.*?) \((2[AB])\)\. (.*)\"$/\3/) &&
	      ($comment !~ s/(.*?) \((97\d)\)\. (.*)\"$/\3/));
	my ($name, $depart) = ($1, $2);
	$comment =~ /^(.*?) /;
	my $comment1 = $1;
	my $cible = "";
	$cible = "vac" if (($comment1 eq "AD") || ($comment1 eq "AD-Hydro"));
	$cible = "mil" if ($comment1 eq "AD-MIL");
	$cible = "basulm" if ($comment1 eq "BASULM") ;
    die "$line\n   ERREUR. Le dernier champ doit contenit la source d'info : 'AD', AD-Hydro, 'AD-MIL' ou 'BASULM'" if ($cible eq "");
	
	my $dim = $dimension eq "" ? "" : $dimension . "m";
   
    #on reconstitue la ligne, et on compare
    my $newLine = "\"$code $shortName\",\"$code\",FR,$lat,$long,${elevation}m,$nature,$qfu,$dim,$frequence,\"$code - $name \($depart\). $comment\"";
	die "$line\n$newLine\n    ERREUR. La ligne reconstituée n'est pas identique a a ligne initiale" if ($line ne $newLine);
    #print "$newLine\n";
	
	$ADs{$code} = { code => $code, cible => $cible, shortName => $shortName, name => $name, lat => $lat, long => $long, elevation => $elevation, nature => $nature, qfu => $qfu, dimension => $dimension,
	               frequence => $frequence, depart => $depart, comment => $comment };
  }
  close $handle;
  
  return \%ADs;
}

####################################################################################################
#           ecriture du fichier .cup de reference a partir d'un hash
#  
# on proce en deux passes, pour avoir les terrains SIA en premier
#
# si parametre "fic", ecrit dans le fichier. Sinon, ecrit et stdout
#
# pas de controle de coherence des parametres du hash
####################################################################################################
sub writeRefenceCupFile
{
  my $ADs = shift;

  my %args = (@_);
  
  my $fic = $args{fic};
  my $handle;
  
  if (defined($fic))
  {
    die "unable to write fic $fic" unless (open ($handle, ">$fic"));
  }
  else
  {
    $handle = \*STDOUT;
  }
  
  # on reconstitue le fichier en deux passes, pour avoir les terrains SIA en premier  
  &_listADs($ADs, $handle, cibles => {"vac" => 1, "mil" => 1});
  &_listADs($ADs, $handle, cibles => { "basulm" => 1 });
  
  close $handle if (defined($fic));
  
  sub _listADs
  {
    my $ADs = shift;
	my $handle = shift;
    my %args = @_;
  
    my $cibles = $args{cibles};
    die "listADs. Il faut passer un hash 'cibles' en argument" unless (defined($cibles));

    foreach my $code (sort keys %$ADs)
    {
      my $AD = $$ADs{$code};
	  my $cible = $$AD{cible};
	  next unless(defined($$cibles{$cible}));
	  
	  #if ($code eq "LF1255") { print Dumper($AD); exit;}
	  my $line = &buildLineReferenceCupFile($AD);
      print $handle "$line\n";
    }
  }
}

sub buildLineReferenceCupFile
{
  my $AD = shift;
  
  #print Dumper($AD); exit;
  my $code = $$AD{code};
  my $dimension = $$AD{dimension};
  $dimension .= "m" if ($dimension ne "");
  my $elevation = $$AD{elevation};
  $elevation .= "m" if ($elevation ne "");

  my $line = "\"$code $$AD{shortName}\",\"$code\",FR,$$AD{lat},$$AD{long},$elevation,$$AD{nature},$$AD{qfu},$dimension,$$AD{frequence},\"$code - $$AD{name} \($$AD{depart}\). $$AD{comment}\"";
  return $line;
}

# lecture du fichier listVACfromPDF.csv (provient du site SIA et des bases militaires) ou listULMfromCSV.csv (provient de basulm, genere depuis readBasulm.pl)
sub readInfosADs
{
  my $fic = shift;

  my %ADs = ();
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
  
  while (my $line = <FIC>)
  {
    chomp ($line);
 	next if ($line eq "");
	my ($code, $cible, $name, $lat, $long, $elevation, $nature, $qfu, $dimension, $frequence, $comment) = split(";", $line);
	$ADs{$code} = { code => $code, cible => $cible, name => $name, frequence => $frequence, elevation => $elevation, lat => $lat, long => $long, comment => $comment, qfu => $qfu, dimension => $dimension, nature => $nature };
	#if ($code eq "LFEZ") {print Dumper($ADs{$code}) ; exit;}
  }
  return \%ADs;
}

##### comparaison du non de terrain, entre 2 sources de données
sub compareNames
{
  my $name1 = shift;
  my $name2 = shift;
  
  my $newname1 = uc(unac_string($name1));
  my $newname2 = uc(unac_string($name2));
  
  $newname1 =~ s/ \- /\-/g;
  $newname2 =~ s/ \- /\-/g;
  
  $newname1 =~ s/\-/ /g;
  $newname2 =~ s/\-/ /g;

  $newname1 =~ s/\'//g;
  $newname2 =~ s/\'//g;

  $newname1 =~ s/ ST / SAINT /;
  $newname2 =~ s/ ST / SAINT /;
    
  $newname1 =~ s/^ST /SAINT /;
  $newname2 =~ s/^ST /SAINT /;

  if ($newname1 !~ /^$newname2$/)
  {
    #print "|$newname1|;|$newname2|\n";
    return 0;
  }
  return 1;
}

# converti des donnes GPS provenant de cartes VAC  - format degre - minute - secondes (ex : 48 43 25 N , 006 12 23 E)
#           en donnes GPS - format fichier CUP : degre - minute - millieme de minutes [E/W] (ex : 4843.417N, 00612.383E)
sub convertGPStoCUP
{
  my $val = shift;
  
  my $final = "";
  $final = $1 if ($val =~ s/ ?([NSEW])$//);
  
  my ($degre, $mn, $sec) = split(" ", $val);
  return undef unless (defined($sec));
  
  if ($sec == 60)
  {
    $sec = 0;
	$mn++;
  }

  if ($mn == 60)
  {
    $mn = 0;
	$degre++;
  }
  
  my $milliemes = sprintf("%.3f", $sec / 60);
  $milliemes =~ s/^0\.//;
    
  return sprintf("%02s%02s.%03s%s", $degre, $mn, $milliemes, $final);
}

# converti des donnes GPS provenant de France.cup - format degre - minute - milliemes de minute (ex : 4845.967N)
#           en donnes GPS - format decimal (48.7661). Le nombre de decimales desire est passe en parametre
sub convertCUPtoDec
{
  my $val = shift;
  my $precision = shift;
  
  $precision = 4 unless(defined($precision));
  
  my $final = "";  
  $final = $1 if ($val =~ s/([NSEW])$//);
  
  $val = sprintf("%.3f", $val);  #on arrondi a 3 decimales ; et on complete si necessaire
  $val = "00" . $val;  # pour traiter des valeurs comme "00002.883E" ; donc moins de 2 chiffres avant le point
  
  return undef unless ($val =~ /(\d*?)(\d\d\.\d\d\d)/);
  my ($degre, $mn) = ($1, $2);
  #printf("%s  %s  %s\n", $degre, $mn, $mn / 60);
    
  my $newVal = $degre + ($mn / 60);
  $newVal = "-" . $newVal if ($final eq "W");
  return  sprintf("%.${precision}f", $newVal);
}

# converti des donnes GPS provenant de cartes VAC  - format degre - minute - secondes (ex : 48 43 25 N , 006 12 23 E)
#           en donnes GPS - format decimal (48.7661). Le nombre de decimales desire est passe en parametre
sub convertGPStoDec
{
  my $val = shift;
  my $precision = shift;
  
  $precision = 4 unless(defined($precision));
  
  my $final = "";
  $final = $1 if ($val =~ s/ ?([NSEW])$//);
  
  my ($degre, $mn, $sec) = split(" ", $val);
  return undef unless (defined($sec));
    
  $mn += ($sec / 60);
  #printf("%s   %s   %s   %s\n", $degre, $mn, $sec, $mn / 60);
  
  my $newVal = $degre + ($mn / 60);
  $newVal = "-" . $newVal if ($final eq "W");
  return  sprintf("%.${precision}f", $newVal);
}


#############################################################################################
#          generation d'une requete http
#Cette fonction permet de gerer les cookies et le User-Agent (entre autres)
# on peut empecher les redirection, avec max_redirect => 0
# - param1 : l'URL
# - params formels, facultatifs :
#     . METHOD : "GET", "POST". defaut = GET
#     . CONTENT_TYPE : par defaut, "text/html"
#     . SSL_NO_VERIFY : a 0 par defaut. Si different de 0, pas de verifications SSL_NO_VERIFY
#     . COOKIES : permet de passer des cookies a la requete
#     . DIE : mettre a 0 pour ne pas arreter si erreur
#############################################################################################
sub sendHttpRequest
{
  my $url = shift;
  my %args = (METHOD => "GET", CONTENT_TYPE => "text/html", SSL_NO_VERIFY => 0, COOKIES => {}, DIE => 1, @_);  
  
  my $content = $args{CONTENT};
  my $cookies = $args{COOKIES};
  my $contentType = $args{CONTENT_TYPE};
  my $method = $args{METHOD};
  my $sslNoVerify = $args{SSL_NO_VERIFY};
  my $dieOnError = $args{DIE};
  
  my $req = new HTTP::Request($method => $url);  
  $req->content_type($contentType);
  $req->content($content) if (defined($content));
  my $browser = new LWP::UserAgent(keep_alive => 0, timeout => 10, max_redirect => 5);
  $browser->ssl_opts( verify_hostname => 0 ,SSL_verify_mode => 0x00) if ($sslNoVerify);
  $browser->cookie_jar($cookies);
  $browser->agent($UserAgent);
  my $res = $browser->request($req);
  die "Erreur inconnue lors de l'acces a $url" unless(defined($res));
  my $content = $res->content();
  #my $content = $res->decoded_content(raise_error => 1 , default_charset => 'windows-874');
  chomp($content);
  my $headers = $res->headers;
  my $codeHTTP = $res->status_line;
  unless ($res->is_success)
  {
	if ($dieOnError)
	{
      print "$content\n\n";
      print "### Erreur http $codeHTTP lors de l'acces a $url ###\n";
	  print Dumper($res);
      exit 1;
	}
	return ($codeHTTP, $content, $browser->cookie_jar);
  }
  return ($codeHTTP, $content, $browser->cookie_jar);
}


#############################################################################################
#          ecriture d'un fichier binaire
# - param1 : le fichier destinataire
# - param2 : le contenu
#############################################################################################
sub writeBinFile
{
  my $fic = shift;
  my $content = shift;
  
	die "unable to write fic |$fic|" unless (open (FIC, ">$fic"));
	binmode FIC;
	print FIC $content;
	close(FIC);
}
