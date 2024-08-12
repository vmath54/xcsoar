package VAC;
#

# Variables et procedures perl en lien avec la mise a disposition de cartes VAC et baseULM
#
# les fichiers .cup lus doivent avoir une des deux entetes suivantes (l'ordre des champs n'importe pas) :
#   name,code,country,lat,lon,elev,style,rwdir,rwlen,freq,desc
#   name,code,country,lat,lon,elev,style,rwdir,rwlen,rwwidth,freq,desc,userdata,pics
#
# les fichiers .cup ecrits seront dans le second format
#
# le format d'un fichier .cup : http://download.naviter.com/docs/cup_format.pdf
# le format d'un fichier .cup SeeYou : https://downloads.naviter.com/docs/SeeYou_CUP_file_format.pdf
#
# site intéressant pour conversions données GPS :
#     https://www.lecampingsauvage.fr/gps-convertisseur
# et pour générer un fichier kmz : Airspace Converter (appli windows)
#     http://www.alus.it/AirspaceConverter/

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
@ISA = ('Exporter');
@EXPORT = qw( &getPDFsource &getDepartements &readCupFile &writeRefenceCupFile &buildLineReferenceCupFile &readInfosADs &compareNames &convertGPStoCUP &convertCUPtoDec &convertGPStoDec &sendHttpRequest &writeBinFile $enteteCUPfile);

use LWP::Simple;
use Text::CSV qw( csv );
#use Encode 'decode_utf8';
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

our $enteteCUPfile = "name,code,country,lat,lon,elev,style,rwdir,rwlen,rwwidth,freq,desc,userdata,pics";
our $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:96.0) Gecko/20100101 Firefox/96.0";

my %natures =
(
  "eau"    => 1,
  "herbe"  => 2,
  "neige"  => 3,
  "dur"    => 5,
);

# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
# reponse de Michel Hirmke, BASULM, pour LF0221 et LF5763 :
#    Pour Langatte, il y a bien deux terrains appartenant au même propriétaire, avec deux arrêtés distincts, un pour les paramoteurs, l'autre pour les autres classes.
#    Pour Corbeny, il s'agit de deux terrains très proches, mais distincts. L'un est à l'usage exclusif de son propriétaire et de ses invités, l'autre a été créé récemment pour une école.
our $noADs =
{
  "LF0221" => { name => "Azur Ulm",                comment => "doublon avec LF0256, Corbeny" },
  "LF0926" => { name => "Cerizols",                comment => "piste reservee ballons" },
  "LF3733" => { name => "Hippolytaine",			   comment => "doublon avec LF3755, St Hippolyte" },
  "LF3952" => { name => "Vauxy - Arbois",          comment => "doublon avec LF3956, Arbois-Ulm" },
  "LF5763" => { name => "Langatte paramoteur",     comment => "meme site que LF5762, Langatte ULM" },
  "LF8569" => { name => "Les Guifettes",           comment => "doublon avec LF8528, Lucon" },
  "LF97102" => { name => "Le Gosier",              comment => "trop proche de LF97101, Grand Baie" },  
  "LFRJ"   => { name => "LANDIVISIAU",             comment => "Transit VFR" },
  "LFRL"   => { name => "LANVEOC POULMIC",         comment => "Transit VFR" },
  "LFTL"   => { name => "Cannes Quai du large",    comment => "helistation" },
  "SOOM"   => { name => "Saint Laurent du Maroni", comment => "Guyane" },
};

####################################################################################################
#  lecture du fichier .cup de reference
# Ce fichier est formaté comme suit :
#
# name,code,country,lat,lon,elev,style,rwdir,rwlen,rwwidth,freq,desc,userdata,pics
#
# <shortName>,<code>,FR,<latitude>,<longitude>,<elevation>,<categorie>,<qfu>,<dimension>,<rwwidth>,<frequence>,<comment>,<userdata>,<pics>
#
#  . style   : 1 pour eau. 2 pour herbe. 3 pour neige. 5 pour dur
#  . elev    : altitude du terrain, en metres
#  . rwdir   : orientation du terrain
#  . rwlen   : longueur du terrain, en metres
#  . rwwidth : largeur du terrain, en metres
#  . desc : la description. Voir parametre optionnel 'ref' pour controle formatage
#
# Le parametre obligatoire de cette fonction est un nom de fichier 
#
#  parametres formels facultatifs :
#     . onlyAD. Si valué, ne traite que ce terrain
#     . ref. Si valué, suppose que c'est le fichier de reference, et que le champ desc est formate comme suit :
#            <code> <name> (<departement>). <infos complementaires>
#               infos complementaires commence par "AD " pour un terrain issu du site SIA, "AD-MIL " pour un terrain militaire, "BASULM " pour un terrain basulm
#
# retourne un hash indexe par code de terrain
####################################################################################################

sub readCupFile
{
  my $fic = shift;
  my %args = (@_);
  
  my $onlyAD = $args{onlyAD};
  my $reference = $args{ref};
  
  my %ADs;  
  my $handle;       # handle du fichier a lire
  my $csv = Text::CSV->new ();  

  die "unable to read fic $fic" unless (open ($handle, "<:utf8", $fic));
  
  my @headings = @{$csv->getline ($handle)};  
  my $row = {};
  $csv->bind_columns (\@{$row}{@headings});
  my $nbADs = 0; 
    
  while ($csv->getline ($handle)) {                   #lecture des lignes
    $nbADs++;
    my $AD = {};
	$$AD{rang} = $nbADs;
    my $code = $$row{code};
	$code =~ s/\"//sg;
	next if (($onlyAD ne "") && ($code ne $onlyAD));
	
    foreach my $field (keys %$row) {                  #lecture des champs
      $$AD{$field} = $row->{$field};
	}

    $$AD{elev} =~ s/m$//;
    $$AD{elev} =~ s/\.\d?$//;
    $$AD{rwlen} =~ s/m$//;
    $$AD{rwlen} =~ s/\.\d?$//;
    $$AD{rwwidth} =~ s/m$//;
    $$AD{rwwidth} =~ s/\.\d?$//;	

    if ($reference) {   # on fait des controles specifiques au fichier de reference
	#print Dumper($AD);

      die "$code\n   ERREUR. Le code terrain n'est pas conforme" if (($code !~ /^LF\S\S$/) && ($code !~ /^LF\d\d\d\d$/) &&
               ($code !~ /^LF2[AB]\d\d$/) && ($code !~ /^LF97\d\d\d$/) && ($code !~ /^LF98\d\d\d$/));
      die "$code : $$AD{style}\n   ERREUR. Le champ 'style' doit avoir une des valeurs : 1, 2, 3 ou 5" 
	          if (($$AD{style} != 1) && ($$AD{style} != 2) && ($$AD{style} != 3) && ($$AD{style} != 5)); 
	  my $desc = $$AD{desc};
      die "$code : $$AD{desc}\n   ERREUR. Le champ desc doit commencer par le code terrain" unless ($desc =~ s/^$code \- //);
      die "$code : $$AD{desc}\n   ERREUR. Le champ desc doit contenir le nom, le departement et un commentaire" 
      if (($desc !~ s/(.*?) \((\d\d)\)\. (.*)$/\3/) && ($desc !~ s/(.*?) \((2[AB])\)\. (.*)$/\3/) &&
          ($desc !~ s/(.*?) \((97\d)\)\. (.*)$/\3/) && ($desc !~ s/(.*?) \((98\d)\)\. (.*)$/\3/));
      my ($realname, $depart, $cat) = ($1, $2, $3);
	  #print "realname = $realname, depart = $depart, cat = $cat\n";
      my $cible = "";
      $cible = "vac" if (($cat =~ /^AD/) || ($cat =~ /^AD-Hydro/));
      $cible = "mil" if ($cat =~ /^AD-MIL/);
      $cible = "basulm" if ($cat =~ /^BASULM/) ;
      die "$code : $$AD{desc}\n   ERREUR. Le champ desc du fichier de ref doit contenit la source d'info : 'AD', AD-Hydro, 'AD-MIL' ou 'BASULM'" if ($cible eq "");
	  $$AD{cible} = $cible;
	  $$AD{depart} = $depart;
	  $$AD{comment} = $$AD{desc};
	  $$AD{desc} = $realname;
	  $$AD{name} =~ s/^$code //;
	  $$AD{cat} = $cat;
	}
    $ADs{$code} = $AD;
  }
  close $handle;
  
  return \%ADs;
}

####################################################################################################
#           ecriture du fichier .cup de reference a partir d'un hash
#  
# on procede en deux passes, pour avoir les terrains SIA en premier
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
    die "unable to write fic $fic" unless (open ($handle, ">:utf8", $fic));
  }
  else
  {
    $handle = \*STDOUT;
  }

  print $handle "$enteteCUPfile\n";
  
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
	  
	  #if ($code eq "LFAB") { print Dumper($AD); exit;}
	  my $line = &buildLineReferenceCupFile($AD);
      print $handle "$line\n";
    }
  }
}

sub buildLineReferenceCupFile
{
  my $AD = shift;
    
  my $code = $$AD{code};
  my $rwlen = $$AD{rwlen};
  $rwlen .= "m" if ($rwlen ne "");
  my $rwwidth = $$AD{rwwidth};
  $rwwidth .= "m" if ($rwwidth ne "");
  my $elev = $$AD{elev};
  $elev .= "m" if ($elev ne "");
  my $freq = $$AD{freq};
  $freq = "\"$freq\"" if ($freq ne "");
  my $country = $$AD{country} eq "" ? "FR" : $$AD{country};
  my $desc = "$code - $$AD{desc} \($$AD{depart}\). $$AD{cat}";

  my $line = "\"$code $$AD{name}\",\"$code\",$country,$$AD{lat},$$AD{lon},$elev,$$AD{style},$$AD{rwdir},$rwlen,$rwwidth,$freq,\"$desc\",,";
  return $line;
}

# lecture du fichier listVACfromPDF.csv (provient du site SIA et des bases militaires) ou listULMfromCSV.csv (provient de basulm, genere depuis getInfosFromApiBasulm.pl)
sub readInfosADs
{
  my $fic = shift;

  my %ADs = ();

  die "unable to read fic $fic" unless (open (FIC, "<:utf8", $fic));
  
  while (my $line = <FIC>)
  {
    chomp ($line);
 	next if ($line eq "");
	my ($code, $cible, $name, $lat, $lon, $elev, $nature, $rwdir, $rwlen, $rwwidth, $freq, $cat) = split(";", $line);
	my $style = $natures{$nature};
    $style = 1 if (! defined($style));
	$ADs{$code} = { code => $code, cible => $cible, name => $name, freq => $freq, elev => $elev, lat => $lat, lon => $lon, cat => $cat, rwdir => $rwdir, rwlen => $rwlen, rwwidth => $rwwidth, style => $style };
	#if ($code eq "LF4161") {print Dumper($ADs{$code}) ; exit;}
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
  
  $newname1 =~ s/ ?\- ?/\-/g;
  $newname2 =~ s/ ?\- ?/\-/g;
  
  $newname1 =~ s/\-/ /g;
  $newname2 =~ s/\-/ /g;

  $newname1 =~ s/\'/ /g;
  $newname2 =~ s/\'/ /g;

#  $newname1 =~ s/([^ ])?ST(E?)(S?) /$1SAINT$2$3 /;
#  $newname2 =~ s/([^ ])?ST(E?)(S?) /$1SAINT$2$3 /;

  $newname1 =~ s/^ST(E?)(S?) /SAINT$1$2 /;
  $newname2 =~ s/^ST(E?)(S?) /SAINT$1$2 /;

  $newname1 =~ s/( )?ST(E?)(S?) /$1SAINT$2$3 /;
  $newname2 =~ s/( )?ST(E?)(S?) /$1SAINT$2$3 /;

  $newname1 =~ s/ +//g;
  $newname2 =~ s/ +//g;
    

  if ($newname1 !~ /^$newname2$/)
  {
    #print "#### |$newname1|;|$newname2| ####\n";
    return 0;
  }
  return 1;
}

# converti des donnes GPS provenant de cartes VAC  - format degre - minute - secondes (ex : 48 43 25 N , 006 12 23 E)
#           en donnes GPS - format fichier CUP : degre - minute - millieme de minutes [E/W] (ex : 4843.417N, 00612.383E)
sub convertGPStoCUP
{
  my $val = shift;
  
  my $final;
  $final = $1 if ($val =~ s/ ?([NSEW])$//);
  
  unless (defined($final))  # parfois, le format est "S 21 05 50" au lieu de "21 05 50 S" ....
  {
    $final = $1 if ($val =~ s/^([NSEW]) //);
  }
  
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
#     . DIE : mettre a 1 pour arreter si erreur
#############################################################################################
sub sendHttpRequest
{
  my $url = shift;
  my %args = (METHOD => "GET", CONTENT_TYPE => "text/html", SSL_NO_VERIFY => 0, COOKIES => {}, DIE => 0, @_);  
  
  my $authorization = $args{AUTHORIZATION};
  my $content = $args{CONTENT};
  my $cookies = $args{COOKIES};
  my $contentType = $args{CONTENT_TYPE};
  my $method = $args{METHOD};
  my $sslNoVerify = $args{SSL_NO_VERIFY};
  my $dieOnError = $args{DIE};
  
  my $req = new HTTP::Request($method => $url);  
  $req->content_type($contentType);
  $req->header('Authorization' => $authorization) if (defined($authorization));
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
	  #print Dumper($res);
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
