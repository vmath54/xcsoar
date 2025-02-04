#!/usr/bin/perl

# Utilitaire XCSoar
#
# generation d'un fichier de details de waypoints a partir d'un fichier .cup passe en parametre
# ce fichier de details permettra dans XCSoar de faire le lien avec le fichier pdf du waypoint s'il existe dans les bases SIA, MIL ou baseULM
# Cet utilitaire utilise un fichier de reference (FranceVacEtUlm.cup) qui r?pertorie tous les terrains VAC (dispos sur site SIA), MIL (militaires) et basULM
#
# le fichier resultat est cree dans le meme repertoire que le .cup passe en parametre
#
# exemple : genereDetailsFromCUP.pl -file ../dossier1/myFichier.cup
#           dans ce cas, le fichier de details sera ../dossier1/myFichier_details.cup
#                                                ou ../dossier1/myFichier_details_noulm.cup si option --noULM
#
# peut egalement creer un fichier archive (.zip) avec tous les terrains VAC et/ou MIL (militaires) et/ou baseULM references, s'ils sont bien sur 
#       stockes dans un ou des dossiers (ou repositories) locaux
#       ce fichier sera ../dossier1/myFichier.zip ou ..../myFichier_noulm.zip
#
# peut aussi creer un fichier similaire a celui d'origine, avec mise a jour des coordonnees, altitude, et frequence
#       si --genereFileCUP, le fichier sera ../dossier1/myFichier_new.cup
#
# Cet utilitaire peut utiliser deux algos differents pour associer un terrain du fichier .cup avec ceux du fichier de reference :
#  - par defaut, comparaison des coordonnees geographiques du terrain avec ceux du fichier de reference
#       La variable $toleranceGeog permet d'indiquer la marge d'erreur acceptable
#
#  - si parametre "-searchByColumn <xxxx>", ou <xxxx> est le nom d'une colonne ; en general, code, qui contient
#            le code OACI ou FFPLUM du terrain dans un des champs du fichier .cup
#
# si execute sans parametre, donne de l'aide
#
# parametres accept?s :
#
# . -file <fichier> : obligatoire. C'est le fichier .cup ? analyser
# . --oldCUPformat : facultatif. Si pr?sent, suppose que le fichier .CUP est en ancien format, sans les champs rwwidth,userdata,pics
# . --zip : facultatif. Si pr?sent, g?n?re un fichier zip contenant les PDF des terrains concern?s
# . --noulm : facultatif. Si pr?sent, ne traite pas les terrains de BASULM
# . --nofreq : facultatif. Si present, ne modifie pas la frequence des terrains\n";
# . --nocode : facultatif. Si present, ne modifie pas le code terrain\n";
# . --genereFileCUP : facultatif. Si pr?sent, reg?n?re un fichier .cup similaire ? celui d'origine, avec mise a jour des infos de coordonn?es, d'altitude, de fr?quence
# . -searchByColumn <column> : facultatif. Ne recherche pas la correspondance de terrain avec les coordonnees GPS, mais dans la colonne <column> du fichier .cup
#        les valeurs possible de column sont : name, code, country, lat, lon, elev, style, rwdir, rwlen, rwwidth, freq, desc, userdata, pics

use lib ".";       # necessaire avec strawberry, pour VAC.pm
use VAC;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use File::Basename;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Time::Piece;
use Data::Dumper;

use strict;

my $ficREF      = "FranceVacEtUlm.cup";  # le fichier de reference. 

my %cibles =      # dirPDF donne le repertoire qui contient les PDF, pour la cible.
(                 # necessaire si $createZip != 0
  vac  =>   { dirPDF => "./vac",    founds => 0 },
  mil =>    { dirPDF => "./mil",    founds => 0 },
  basulm => { dirPDF => "./basulm", founds => 0 },
);

my @columns = ( "name", "code", "country", "lat", "lon", "elev", "style", "rwdir", "rwlen", "rwwidth", "freq", "desc", "userdata", "pics" );


# $toleranceGeog est la tol?rance en centi?me de degr?s lors de comparaisons de 2 points g?ographiques
#     1 mn de latitude  =~ 1km300 ; 1 mn de longitude =~ 1km900
#     $toleranceGeog = 1 donne 0.01 degr? de latitude =~ 800m, 0.01 degr? de longitude =~ 1km100
#   ne pas monter trop haut, sinon beaucoup de faux-positifs. Une valeur de 1 ou 2 semble raisonnable
my $toleranceGeog = 1;

my $verboseRewrite1 = 1;   # a 1 pour de l'info si modifications de coordonn?es geographiques ou d'altitude si > 2m
my $verboseRewrite2 = 1;   # a 1 pour de l'info si modification de fr?quence

my ($oldCUPformat, $nofreq, $nocode);

{
  my ($file, $searchByColumn, $withZip, $noulm, $genereFileCUP, $genereFileCSV, $help);
  my $ret = GetOptions
     ( 
       "file=s"            => \$file,
       "searchByColumn=s"  => \$searchByColumn,
	   "oldCUPformat"      => \$oldCUPformat,
	   "zip"               => \$withZip,
	   "noulm"             => \$noulm,
	   "nofreq"            => \$nofreq,
	   "nocode"            => \$nocode,
	   "genereFileCUP"     => \$genereFileCUP,
       "h|help"            => \$help,
     );

  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);
  
  if ($file eq "")
  {
    print 'il faut passer le nom du fichier .cup en parametre "file"' . "\n\n";
	&syntaxe();
  }
  
  my $columnRank = -1;
  if ($searchByColumn ne "") {
	  
	for (my $i = 0; $i < scalar(@columns); $i++) {
	  if ($columns[$i] eq $searchByColumn) {
		$columnRank = $i;
		last;
	  }
	}
	if ($columnRank == -1) {
	  print "la valeur de searchByColumn n'est pas valide\n\n";
	  &syntaxe();
	}
    print "searchByColumn = $searchByColumn, columnRank = $columnRank\n";
  }
  
  die "fichier |$file| non trouve" unless (-f $file);
  my ($ficDetail, $ficZip) = &computeFileNames($file, $noulm, $withZip);     # on calcule le nom des fichiers detail et .zip a partir de celui du .cup
  
  #### on r?cup?re les infos du fichier de r?f?rence.
  my $REFs = &readCupFile($ficREF, ref => 1);
  #print Dumper($$REFs{LF6721}); exit;
  
  my $ADs = &readCupFile($file);        # lecture du fichier .cup en entr?e
  # print Dumper($$ADs{'ALBE ULM'}); exit;
  
  if (defined($searchByColumn))  # lecture et traitement du fichier, en recherchant le code terrain dans une colonne
  {
    &traiteCUPfileByColumn($ADs, $REFs, $searchByColumn); 
  }
  else     # lecture et traitement du fichier en comparant les coordonnees geographiques
  {
    &traiteCUPfileByCoordsGeog($ADs, $REFs);
  }
  
  &genereFicDetails($ficDetail, $ADs, $REFs, \%cibles, $noulm);

  my $nbre = $cibles{vac}{founds} + $cibles{mil}{founds} + $cibles{basulm}{founds};
  print "$nbre terrains trouves\n";
  print "    $cibles{vac}{founds} fichiers provenant du SIA\n";
  print "    $cibles{mil}{founds} fichiers provenant des bases militaires\n";
  print "    $cibles{basulm}{founds} fichiers provenant de baseULM\n";
  print "\n";
  print "Fichier de details : $ficDetail\n";

  
  if ($withZip)
  {
    print "Fichier zip : $ficZip\n";	
	&createZip($ficZip, $ADs, $REFs, \%cibles, $noulm);
  }
  
  &rewriteCUPfile($ADs, $REFs, $file)   if ($genereFileCUP);   # on r? ?crit le fichier d'origine  
}

# analyse du fichier CUP passe en parametre
# on compare avec les coordonnes geographiques (GPS) des terrains du fichier de reference
# %cibles est passe en parametre afin d'indiquer le nombre de sites trouves pour chacune
sub traiteCUPfileByCoordsGeog
{
  my $ADs = shift;    # contient les infos lues du fichier .cup
  my $REFs = shift;

  # $coords va contenir une reference entre coordonnees geographiques t le code d'un terrain de la base de reference
  #                    {$lat => {$long => $code}}
  my $coords = &computeCoords($REFs);
  
  #my $latdec = 4600; my $longdec = 533; my $toleranceGeog = 2;  # Amberieu. LFXA = 4598 et 534
  #my $code = &matchCoords($coords, $latdec, $longdec, $toleranceGeog);
  #print "$latdec, $longdec => $code (on cherche 4598 et 534)\n"; exit;

  foreach my $name (sort keys %$ADs)
  #my $name = "ALBE ULM";
  {
	my $AD = $$ADs{$name};
    my $lat = $$AD{lat};
	my $lon = $$AD{lon};
	my $style = $$AD{style};
	
	next if (($style <1) || ($style > 5));    # on ne prend que les waypoints de type terrain d'atterrissage
	
	my $latdec = &convertCUPtoDec($lat, 2);      # conversion en degres.centiemes
	my $longdec = &convertCUPtoDec($lon, 2);
	die "traiteCUPfile. $name : probleme dans coordonnes geographiques. $lat => $latdec, $lon => $longdec" if (! defined($lat) || ! defined($lon));
	$$AD{lat_dec} = $latdec;
	$$AD{long_dec} = $longdec;

	$latdec = sprintf ("%.0f", $latdec * 100);    # on retire le point decimal
	$longdec = sprintf ("%.0f", $longdec * 100);
	
	my $code = &matchCoords($coords, $latdec, $longdec, $toleranceGeog);
	if ($code ne "")    # on a trouve un terrain dans fichier de ref, avec les m?mes coordonnees geographiques
	{
	  my $REF = $$REFs{$code};
	  if (defined($$REF{ADmatch}))   # une autre ligne du fichier .cup matche avec le meme terrain de REF
	  {
	    my $otherName = $$REF{ADmatch};
		my $name2keep = &compareADs($$ADs{$otherName}, $$ADs{$name});   # on compare les deux terrains, pour en choisir un
		
		unless ($name2keep)
		{
	      print "ATTENTION. $otherName et $name matchent tous les deux le terrain $code, et on n'a pas pu definir de priorite !!!\n";
		  next;
		}
	    next if ($name2keep eq $otherName );  # c'est le premier terrain qui est retenu
	    delete $$ADs{$otherName}{codeREF};     # c'est le terrain courrant qui est retenu. On supprime le lien du terrain precedent
	  }

	  $$REF{ADmatch} = $name;         #on memorise le terrain dans le hash de reference
	  $$AD{codeREF} = $code;   # et le code de reference dans le hash des terrains
	}
  }
  #print Dumper($$ADs{"ALBE ULM"}), , Dumper($$REFs{LF6721}); exit;
  #print Dumper($$ADs{"FERME BEAUCHAMP"}), Dumper($$REFs{LF5453}), Dumper($$coords{4877}); exit;
}

# compare 2 terrains du fichier .cup qui matchent avec une terrain de REF
# essai de determiner un terrain prioritaire
sub compareADs
{
  my $AD1 = shift;
  my $AD2 = shift;
  
  ###  si on est sur le fichier France.cup, on donne priorite au terrain en "Landefeld" ou "Flugplatz"
  return $$AD1{name}   # on est sur le fichier France.cup
    if ((($$AD1{desc} eq "Landefeld") || ($$AD1{desc} eq "Flugplatz")) && ($$AD2{desc} ne "Landefeld") && ($$AD2{desc} ne "Flugplatz"));
  return $$AD2{name}
    if ((($$AD2{desc} eq "Landefeld") || ($$AD2{desc} eq "Flugplatz")) && ($$AD1{desc} ne "Landefeld") && ($$AD1{desc} ne "Flugplatz"));
	
  ### on donne ensuite priorite aux type de terrain 2 (terrain d'aviation en herbe) 3 () et 5 (terrain d'aviation en dur)
  return $$AD1{name}
    if ((($$AD1{style} == 2) || ($$AD1{style} == 5)) && ($$AD2{style} =! 2) && ($$AD2{style} != 5));
  return $$AD2{name}
    if ((($$AD2{style} == 2) || ($$AD2{style} == 5)) && ($$AD1{style} =! 2) && ($$AD1{style} != 5));
  ### puis aux terrains de type 3 (atterrissage en campagne)
  return $$AD1{name}
    if (($$AD1{style} == 3) && ($$AD2{style} =! 2) && ($$AD2{style} =! 3) && ($$AD2{style} != 5));
  return $$AD2{name}
    if (($$AD2{style} == 3) && ($$AD1{style} =! 2) && ($$AD1{style} =! 3) && ($$AD1{style} != 5));
	
  ## maintenant, priorite a celui qui a une frequence, une dimension ou un qfu value
  return $$AD1{name} if (($$AD1{freq} ne "") && ($$AD2{freq} eq ""));
  return $$AD2{name} if (($$AD2{freq} ne "") && ($$AD1{freq} eq ""));
  return $$AD1{name} if (($$AD1{rwdir} ne "") && ($$AD2{rwdir} eq ""));
  return $$AD2{name} if (($$AD2{rwdir} ne "") && ($$AD1{rwdir} eq ""));
  return $$AD1{name} if (($$AD1{rwlen} ne "") && ($$AD2{rwlen} eq ""));
  return $$AD2{name} if (($$AD2{rwlen} ne "") && ($$AD1{rwlen} eq ""));
  
  return undef;
}

####### recherche la correspondance d'un couple latitude = longitude avec la reference $coords
# $tolerance donne la marche de tolerance, en 100eme de degres (=~ 800m pour latitude, =~ 1km100 pour longitude)
sub matchCoords
{
  my $coords = shift;
  my $lat = shift;
  my $lon = shift;
  my $tolerance = shift;
    
  return $$coords{$lat}{$lon} if (defined($$coords{$lat}{$lon}));  # egalite 'distance = 0) ; on fait simple

  for (my $indLat = 0; $indLat <= $tolerance; $indLat++)
  {
    for (my $indLong = 0; $indLong <= $tolerance; $indLong++)
    {
	  return $$coords{$lat + $indLat}{$lon + $indLong} if (defined($$coords{$lat + $indLat}{$lon + $indLong}));
	  return $$coords{$lat + $indLat}{$lon - $indLong} if (defined($$coords{$lat + $indLat}{$lon - $indLong}));
	  return $$coords{$lat - $indLat}{$lon + $indLong} if (defined($$coords{$lat - $indLat}{$lon + $indLong}));
	  return $$coords{$lat - $indLat}{$lon - $indLong} if (defined($$coords{$lat - $indLat}{$lon - $indLong}));
    }
  }
  return undef;
}

# construction d'une reference entre coordonnees geographiques ({$lat => {$long => $code}}) et le code d'un terrain de la base de reference
sub computeCoords
{
  my $REFs = shift;
  
  my %coords;
  
  foreach my $code (keys %$REFs)
  {
    my $REF = $$REFs{$code};
	my $lat = &convertCUPtoDec($$REF{lat}, 2);      # conversion en degres.centiemes
	my $lon = &convertCUPtoDec($$REF{lon}, 2);
	die "computeCoords. $code : probleme dans coordonnes geographiques. $$REF{lat} => $lat, $$REF{lon} => $lon" if (! defined($lat) || ! defined($lon));
	$$REF{lat_dec} = $lat;
	$$REF{long_dec} = $lon;
	$lat = sprintf ("%.0f", $lat * 100);    # on retire le point decimal
	$lon = sprintf ("%.0f", $lon * 100);
	
	if (defined($coords{$lat}{$lon}))
	{
	  my $altCode = $coords{$lat}{$lon};
	  die "computeCoords. $code et $altCode : Conflit dans les coordonnes geographiques : $lat et $lon";
    }
	$coords{$lat}{$lon} = $code;
  }
  return \%coords;
}

# analyse du fichier CUP passe en parametre
# analyse en recherchant le code terrain dans un champ du fichier ($column)
# %cibles est passe en parametre afin d'indiquer le nombre de sites trouves pour chacune
sub traiteCUPfileByColumn
{
  my $ADs = shift;
  my $REFs = shift;
  my $column = shift;
  
  foreach my $name (sort keys %$ADs)
  #my $name = "ALBE ULM";
  {
	my $AD = $$ADs{$name};
	my $style = $$AD{style};

	next if (($style <1) || ($style > 5));    # on ne prend que les waypoints de type terrain d'atterrissage
	
    my $code = $$AD{$column};     # la cle de recherche. En general, le code terrain

#	next unless (($val =~ /^(LF\S\S)$/) || ($val =~ /^(LF\S\S) /) || ($val =~ / (LF\S\S)$/) || ($val =~ / (LF\S\S) /) || ($val =~ / (LF\S\S)$/) ||
#	    ($val =~ /^(LF\d\d\d\d)$/) || ($val =~ /^(LF\d\d\d\d) /) || ($val =~ / (LF\d\d\d\d)$/) || ($val =~ / (LF\d\d\d\d) /) || ($val =~ / (LF\d\d\d\d)$/));
#	my $code = $1;

    my $REF = $$REFs{$code};
	unless (defined($REF))
	{
	  print "### $code pas trouve dans le fichier de reference\n";
	  next;
	}
	$$REF{ADmatch} = $name;         #on memorise le terrain dans le hash de reference
	$$ADs{$name}{codeREF} = $code;   # et le code de reference dans le hash des terrains
  }
}

sub createZip
{
 my $ficZip = shift;
  my $ADs = shift;
  my $REFs = shift;
  my $cibles = shift;
  my $noulm = shift;
  
  my $zip = Archive::Zip->new();
  foreach my $name (sort ({$$ADs{$a}{rang} <=> $$ADs{$b}{rang} } keys %$ADs))   # on lit dans le meme ordre que fichier initial
  {
	my $AD = $$ADs{$name};
    next unless (defined($$AD{codeREF}));   # ce n'est pas un terrain reference
	my $code = $$AD{codeREF};
    my $REF = $$REFs{$$AD{codeREF}};
	my $cible = $$REF{cible};	
	my $dir = $$cibles{$cible}{dirPDF};
	my $file = "$dir/$$AD{code}.pdf";
	unless (-f $file)
	{
	  print "### ERREUR ### $file pas trouve\n";
	  next;
	}
		my $file_member = $zip->addFile($file, "$cible/$code.pdf");
  }
  die "probleme ecriture du fichier $ficZip" unless ( $zip->writeToFileNamed($ficZip) == AZ_OK );
}

# Calcul du nom des fichiers detail et .zip a partir de celui du .cup
sub computeFileNames
{
  my $cupFile = shift;
  my $noulm = shift;
  
  my $date = localtime->ymd('');
  
  my($filename, $dirs) = fileparse($cupFile);   # on recupere le chemin et le 'petit' nom du fichier
  $dirs =~ s/\\/\//g;
  $dirs =~ s/\/$//;
  die "$filename : doit avoir l'extension .cup ou .CUP" unless ($filename =~ /(.*)\.cup/i);
  my $name = $1;    # le nom de fichier, sans extension
  my $comp = "";
  $comp = "_noulm" if ($noulm);
  return ("$dirs/${name}${comp}_details.txt", "$dirs/${date}-${name}${comp}.zip");
}
 
############ optionnel. Re ecriture du fichier .cup en stdout
# interet : pouvoir ecraser certains champs du fichier d'origine a partir de la base de reference
sub rewriteCUPfile
{
  my $ADs = shift;
  my $REFs = shift;
  my $file = shift;
  
  die "rewriteCUPfile. Manque parametre file" if ($file eq "");
  
  $file =~ s/\.cup$/_new\.cup/;
  die "unable to write fic |$file|" unless (open (FIC, ">:utf8", $file));
  print "\nEcriture du fichier $file\n";

  print FIC "$enteteCUPfile\n";
  
  foreach my $ad (sort ({$$ADs{$a}{rang} <=> $$ADs{$b}{rang} } keys %$ADs))  # on lit dans le m?me ordre que fichier initial
  #my $ad = "PIRMASENS";
  {
	my $AD = $$ADs{$ad};
    #print Dumper($AD);

    if (defined($$AD{codeREF}))   # li? avec un terrain referenc?
	{
	  my $codeRef = $$AD{codeREF};
	  my $REF = $$REFs{$codeRef};
	  #print Dumper($REF);
	  
	  if ($$AD{code} ne $codeRef)
	  {
	    printf "%-6s;%-25s. code : '%s' <- '%s'\n", $codeRef, $$AD{name}, $$AD{code}, $codeRef
		     if ($verboseRewrite1);
		$$AD{code} = $codeRef unless ($nocode);
	  }
	  
	  if (($$AD{lat} ne $$REF{lat}) || ($$AD{lat} ne $$REF{lat}))
	  {
	    printf "%-6s;%-25s. Lat ou long : %-22s <- %s\n", $codeRef, $$AD{name}, "$$AD{lat},$$AD{lon}", "$$REF{lat},$$REF{lon}"
		     if ($verboseRewrite1);
		$$AD{lat} = $$REF{lat};
		$$AD{lon} = $$REF{lon};
	  }
	  
	  if (abs($$AD{elev} - $$REF{elev}) > 2)
	  {
	    printf "%-6s;%-25s. Altitude : %-6s <- %s\n", $codeRef, $$AD{name}, $$AD{elev}, $$REF{elev}
		     if ($verboseRewrite1);
	  }
	  $$AD{elev} = $$REF{elev};
	  	  
	  my $newFreq = $$REF{freq};
	  if ($$AD{freq} ne $newFreq)
	  {
	    printf "%-6s;%-25s. Frequence : %-6s  <- %s\n", $codeRef, $$AD{name}, $$AD{freq}, $newFreq
		     if ($verboseRewrite2);

		$$AD{freq} = $$REF{freq} unless ($nofreq);
	  }
	  if (($$AD{rwdir} ne $$REF{rwdir}) || ($$AD{rwlen} ne $$REF{rwlen}) || ($$AD{rwwidth} ne $$REF{rwwidth}))
	  {
	    printf ("%-6s;%-25s. rwdir, rwlen ou rwwidth : %s <- %s\n", $codeRef, $$AD{name}, "$$AD{rwdir}, $$AD{rwlen}, $$AD{rwwidth}", "$$REF{rwdir}, $$REF{rwlen}, $$REF{rwwidth}")
		     if ($verboseRewrite1);
		$$AD{rwdir} = $$REF{rwdir};
		$$AD{rwlen} = $$REF{rwlen};
		$$AD{rwwidth} = $$REF{rwwidth};
	  }
	}
	$$AD{country} = "FR" if ($$AD{country} eq "");
	
	my $freq = $$AD{freq} eq "" ? "" : "\"$$AD{freq}\"";
	my $rwlen = $$AD{rwlen};
	my $elev = $$AD{elev};
	my $rwwidth = $$AD{rwwidth};
	$rwlen .= ".0m" if ($rwlen ne "");
	$elev .= ".0m" if ($elev ne "");
	$rwwidth .= ".0m" if ($rwwidth ne "");
		
    print FIC "\"$$AD{name}\",$$AD{code},$$AD{country},$$AD{lat},$$AD{lon},$elev,$$AD{style},$$AD{rwdir},$rwlen,$rwwidth,$freq,\"$$AD{desc}\",$$AD{userdata},$$AD{pics}\n";
  }
  close FIC;
}

############### ecriture du fichier de details
sub genereFicDetails
{
  my $fic = shift;
  my $ADs = shift;
  my $REFs = shift;
  my $cibles = shift;
  my $noulm = shift;

  die "unable to write fic |$fic|" unless (open (FIC, ">:utf8", $fic));

  foreach my $name (sort ({$$ADs{$a}{rang} <=> $$ADs{$b}{rang} } keys %$ADs))   # on lit dans le m?me ordre que fichier initial
  {
	my $AD = $$ADs{$name};
    next unless (defined($$AD{codeREF}));   # ce n'est pas un terrain reference
    my $REF = $$REFs{$$AD{codeREF}};
	#print "$$AD{name};$$AD{codeREF}\n";
	my $cible = $$REF{cible};
	die "$$REF{code};$name. Cible |$cible| inconnue" if (($cible eq "") || (! defined($$cibles{$cible})));
	next if (($noulm) && ($cible eq "basulm"));
	$$cibles{$cible}{founds}++;

	print FIC "[$$AD{name}]\n";
	print FIC "file=$cible/$$REF{code}.pdf\n";
	print FIC "\n";
  }
  close FIC;
}



sub syntaxe
{
  print "genereDetailsFromCUP.pl\n";
  print "Ce script permet de generer un fichier de details de waypoints a partir d'un fichier waypoints '.cup'\n\n";
  print "les parametres sont :\n";
  print "  . -file <fichier>. obligatoire. C'est le fichier .cup a analyser\n";
  print "  . --oldCUPformat : facultatif. Si pr?sent, suppose que le fichier .CUP est en ancien format, sans les champs rwwidth,userdata,pics\n";
  print "  . --zip : facultatif. Si present, genere un fichier zip contenant les PDF des terrains concernes\n";
  print "  . --noulm : facultatif. Si present, ne traite pas les terrains de basULM\n";
  print "  . --nofreq : facultatif. Si present, ne modifie pas la frequence des terrains\n";
  print "  . --nocode : facultatif. Si present, ne modifie pas le code terrain\n";
  print "  . --genereFileCUP : facultatif. Si present, regenere un fichier .cup similaire ? celui d'origine, avec mise a jour des infos de coordonnees, d'altitude, de frequence\n"; 
  print "  . -searchByColumn <column> : facultatif. Ne recherche pas la correspondance de terrain avec les coordonnees GPS, mais dans la colonne <column> du fichier .cup\n";
  print "                les valeurs possible de column sont : name, code, country, lat, lon, elev, style, rwdir, rwlen, rwwidth, freq, desc, userdata, pics\n",  
  exit;
}