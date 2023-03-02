#!/usr/bin/perl

# recuperation des informations relatives aux terrains a partir des fichier VAC pdf telecharges sur le site SIA
#sauvegarde dans listVACfromPDF.csv
#
# utilise xpdf pour decoder les fichiers pdf : https://www.xpdfreader.com/
#				https://www.xpdfreader.com/pdftotext-man.html
#
# fait 2 passages avec xpdf, pour faciliter la recuperation des informations :
#    - avec l'option '-layout' : permet de recuperer les infos generales, en entete
#    - avec l'option '-table'  : pour recuperer les infos de qfu, dimension et nature du terrain
#
# on utilise egalement le fichier FranceVacEtUlm.cup en entree pour :
#   - detecter les nouvelles fiches
#   - ajouter les quelques infos qui pourraient manquer depuis les fichiers PDF
#        Concerne qfu, dimension et nature pour qqs terrains : LFIP, LFMX, LFNZ
#        mettre $verbose a 1 pour controler

use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;


my $verbose = 1;    # a 0 pour mode silencieux
                    # a 1 pour avoir les infos de MaJ qui ne peuvent pas etre recuperees des fichiers PDF (recupérées du fichier FranceVacEtUlm.cup)
										
my $debugAD;
my $debugFile;
#$debugAD = "LFAB";                        # si décommenté, ne traite que le terrain spécifié. Ne supprime pas le fichier $tempfile, dump les infos
#$debugFile = "listVACfromPDF_debug.csv";   # si decommenté, permet de comparer des infos entre ce traitement et un fichier de reference									  

my $dirVAC       = "vac";                 # le dossier qui contient les fichiers pdf VAC
my $dirMIL       = "mil";                 # le dossier qui contient les fichiers pdf MIL

my $ficOUT = "listVACfromPDF.csv";
my $ficReference = "FranceVacEtUlm.cup";  # ce fichier va permettre d'ajouter les informations qu'on n'a pas pu récupérer des fichiers PDF

# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
my $noADs = $VAC::noADs;

#my $bin = 'd:/soft/xpdfbin-win-3.04/bin64/pdftotext.exe';
my $bin = 'd:/soft/xpdf-tools-win-4.04/bin64/pdftotext.exe';
my $options_1 = '-q -layout -nodiag';      # options a passer au binaire. "-q" : quiet, "-layout" pout maintenir le mieux possible la mise en page
my $options_2 = '-q -table -nodiag';       # options a passer au binaire. "-q" : quiet, "-table" pout maintenir le mieux possible la mise en page
                                           #                              "-nodiag" supprime le texte qui n'est pas horizontal

my %cats = (  1 => "eau", 2 => "herbe", 3 => "neige", 5 => "dur" );

my $tempfile_1 = "tmp1.txt";
my $tempfile_2 = "tmp2.txt";

my $debugADs = &readInfosADs("listVACfromPDF_init.csv") if (defined($debugFile));

########################### main #####################################
{
  my $VACs = {};
  
  die "$bin not present" unless (-f $bin);

  my $ADRefs = &readRefenceCupFile($ficReference);  # infos de reference
  my $ADComp = readInfosADs("listVACfromPDF_init.csv");

  print "Recuperation des infos depuis les cartes VAC\n";
  &getInfosFromVACfiles($dirVAC, $VACs, $ADRefs, "vac");
  print "Recuperation depuis les fichiers de bases militaires\n";
  &getInfosFromVACfiles($dirMIL, $VACs, $ADRefs, "mil");
  
  my $nbre = scalar (keys %$VACs);
  print "$nbre fiches trouvées\n";

  die "unable to write fic $ficOUT" unless (open (FICOUT, ">$ficOUT"));  
  foreach my $code (sort keys %$VACs)
  {
    my $VAC = $$VACs{$code};
    print FICOUT "$$VAC{code};$$VAC{cible};$$VAC{name};$$VAC{lat};$$VAC{long};$$VAC{elevation};$$VAC{nature};$$VAC{qfu};$$VAC{dimension};$$VAC{frequence};$$VAC{comment}\n";  
  }
}

############## recuperation des infos d'aerodromes depuis les fichiers pdf VAC #####
sub getInfosFromVACfiles
{
  my $dir = shift;
  my $VACs = shift;
  my $ADRefs = shift;
  my $cible = shift;
  
  my @fics = glob("$dir/*.pdf");
  if (defined($debugAD))
  {
	@fics = ("$dir/$debugAD.pdf");
  }

  unlink $tempfile_1;
  unlink $tempfile_2;

  foreach my $fic (@fics)
  {
    my ($rep,$code) = $fic =~ /(.+[\/\\])([^\/\\]+)$/; 
	$code =~ s/\.pdf$//i;
	$code = uc($code);                 # code du terrain, a partir du nom de fichier
    next if (defined($$noADs{$code}));
	next if (defined($$VACs{$code}));   # carte deja lue. Ex : LFQE, dans cartes vac et mil

    my $cmd = "$bin $options_1 $fic $tempfile_1";
	system($cmd);
	die "commande |$cmd| echouee" if ($? == -1);

    my $ADRef = $$ADRefs{$code};
    print "WARNING. $code n'est pas connu du fichier de référence\n" unless (defined($ADRef));	
    my $infos = {};     # les infos recoltees pour un terrain
    $$infos{code} = $code;
    $$infos{cible} = $cible;

    &getInfosFromOneVACfile_1($code, $VACs, $ADRef, $cible, $infos, $tempfile_1);  # recherche des infos d'entete du terrain, depuis le fichier genere a partir du pdf
    my $cmd = "$bin $options_2 $fic $tempfile_2";
    system($cmd);
    die "commande |$cmd| echouee" if ($? == -1);
    &getInfosFromOneVACfile_2($code, $VACs, $ADRef, $cible, $infos, $tempfile_2);  # recherche des infos de dfu, dimension, nature, depuis le fichier genere a partir du pdf

    if (defined($debugAD))   # on debug un AD precis
    {
      print "#### infos de la carte VAC ####\n";
	  print Dumper($infos);
      print "\n#### fichier de ref (.cup) : ####\n";
	  print Dumper($ADRef);
	  if (defined($debugFile))
	  {
        print "\n#### ancien fichier : ####\n";
	    print Dumper($$debugADs{$code});
	  }
	}

    if ($verbose)
	{
      my $mess = "";       # message a envoyer si des infos doivent etre recuperees du fichier de reference
      foreach my $info ("qfu", "dimension", "nature")
      {
        if ((! defined($$infos{$info})) && (defined($$ADRef{$info})))    # on recupere du fichier de reference
	    {
	      if ($info eq "nature")
	      {
	        if (defined($cats{$$ADRef{nature}}))
	        {
	          $$infos{nature} = $cats{$$ADRef{nature}};
	          $mess .= "$info : $$infos{$info}    ";
		    }
	      }
	      else
	      {
	        if ($$ADRef{$info} ne "")
		    {
	          $$infos{$info} = $$ADRef{$info} ;
		      $mess .= "$info : $$infos{$info}    ";
		    }
		  }
		}
	  }
      print "$code. Informations recuperees du fichier de reference : $mess\n" if  ($mess ne "");
	}

    my @infosRequired = ("name", "frequence", "elevation", "lat", "long", "cat", "qfu", "dimension", "nature", "comment");
	
	foreach my $infosRequired (@infosRequired)
    {
	  unless (defined($$infos{$infosRequired}))
	  {
	    print "$code. Impossible de recuperer l'info \"$infosRequired\" depuis le fichier $fic\n";
	    print "Arret du programme\n";
	    print Dumper($infos);
	    exit 1;
	  }
	}

    &compareResultat($code, $infos, ["name", "elevation", "lat", "long", "frequence", "comment"]) if (defined($debugFile));

    $$VACs{$code} = $infos;
  
    exit 1 if (defined($debugAD));

    unlink $tempfile_1;
    unlink $tempfile_2;
  }  
}


sub getInfosFromOneVACfile_1
{
  my $code = shift;
  my $VACs = shift;
  my $ADRef = shift;
  my $cible = shift;
  my $infos = shift;
  my $fic = shift;
  
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
   
  my $nblines = 0; my $nbpage = 1;
  
  while (my $line = <FIC>)
  {
	$nblines++;
	if ($line =~ s/\f//) {   # saut de page
	  $nbpage++;
	  #print "###page $nbpage###\n";
	}
	
    chomp ($line);
 	next if ($line eq "");
    if ($nblines == 1)
	{
	############### nom du terrain ###################
	# c'est la fin de la premiere ligne
	  #my @worlds = split /(  )+/, $line;
	  my @worlds = split / {2,}/, $line;	  
	  my $name = $worlds[-1];           # dernier element
	  #print "$code. |$name|\n";
      $name =~ s/Usage restreint //;     # cas particulier de LFIT
	  #$name =~ s/^ *//;
	  $$infos{name} = $name;
    }
	
	if ($nblines < 4)
	{
	################ categorie : "AD", "AD-Hydro"
	  if (!defined($$infos{cat}))
	  {
	    $$infos{cat} = "AD" if (($line =~ /ATTERRISSAGE A VUE/) ||($line =~ /APPROCHE A VUE/));
	    $$infos{cat} = "AD-Hydro" if ($line =~ /AMERRISSAGE A VUE/);
	  }
	  $$infos{cat} = "AD-MIL" if ($cible eq "mil");
	
	############## comment : "Usage restreint", "Ouvert à la CAP", "Réservé administration" "MIL fermé à la CAP"
	  if ((! defined($$infos{comment})) &&
	      (($line =~ /([Oo]uvert à la CAP)/) ||($line =~ /([uU]sage restreint)/) || ($line =~ /(Réservé administration)/)|| ($line =~ /(MIL fermé à la CAP)/) ))
	  {
	    $$infos{comment} = ucfirst(unac_string($1));
	  }
	}

	if ($nbpage == 1)
	{
	################# altitude #######################
	# ALT AD : 1247 (45 hPa) LFEZ
	# ALT AD : 1236 (44hPa) LFGW
	# ALT AD: 4255 (146 hPa) LAT : 45 15 14 N LONG : 006 48 04 E
	# ALT AD : -3 (0 hPa) LAT : 51 02 26 N LONG : 002 33 01 E
	# ALT SUP : 4830 (172 hPa) ALT INF : 4726 (168 hPa)
	# ALT AD SUP : 5193 (185 hPa) ALT AD INF : 5039 (180 hPa)
	# ALT Water AD : 0 (1 hPa) LFTB
	# Attention : altitude en pieds
	  if ((! defined($$infos{elevation})) &&
	      (($line =~ /ALT AD : (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT AD: (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT Water AD : (\-*?\d+?) \(\d+? ?hPa\)/) || 
	       ($line =~ /ALT SUP : (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT AD SUP : (\-*?\d+?) \(\d+? ?hPa\)/)))
	  {
	    $$infos{elevation} = $1;
	  }
	
	###################### latitude et longitude ##############
	# LAT : 48 43 25 N LONG : 006 12 23 E
	# LAT et LONG peuvent etre sur des lignes differentes
	  #on peut avoir 'LAT' sur une ligne, et ': 49 02 44 N' sur une autre
	# et on peut avoit ceci, uniquement sur une ligne (les infos LAT et LONG sont sur d'autres lignes)
	# 45 55 51 N 006 06 23 E
	  unless (defined($$infos{lat}))
      {
	    $$infos{lat} = $1 if ($line =~ /: (\d\d \d\d \d\d N)/);
	  }
	  unless (defined($$infos{long}))
	  {
	    $$infos{long} = $1 if ($line =~ /: (\d\d\d \d\d \d\d [WE])/);
	  }	
	  if ((! (defined($$infos{lat}))) && (! (defined($$infos{long}))))
	  {
	    if ($line =~ /^(\d\d \d\d \d\d N) (\d\d\d \d\d \d\d [WE])$/)
	    {
	      $$infos{lat} = $1;
	      $$infos{long} = $2;
	    }
	  }

	################# frequence ######################
	# APP : NIL TWR : NIL A/A : 136.1      (LFEZ)
	# APP : NIL TWR : NIL A/A 123.175      (LFAS)
	# A/A : 123.350 (commune avec / common with LENS) 
	# APP : NIL TWR : NIL A/A : 123.425. Voir /See TXT. Bétignicourt
	# APP : NIL TWR : NIL A/A (123.405 ) FR seulement/only.  (LFAY)
	# AUTO - INFO : 125.625
    # A/A : COETQUIDAN ou /or AUTO INFO 120.375  (LFXQ)
	# A/A : (Activité militaire/Military activity) / Auto info 118.625  (LFYS)
	# APP : LORRAINE Approche/Approach - OCHEY Approche/Approach 127.250 TWR : NIL AFIS : 119.6 Absence AFIS : A/A (119.6) FR seulement /only      (LFSN)
	# dans certains cas (ex : LFAK), il n'y a pas de frequence A/A ni TWR ni AFIS :
	# APP : KOKSIJDE Approche / Approach 122.100  (LFAK)

	  $$infos{AA} = "NIL" if (! defined($$infos{AA}) && ($line =~ /A\/A : NIL/));
	  $$infos{TWR} = "NIL" if (! defined($$infos{TWR}) && ($line =~ /TWR : NIL/));
	  $$infos{AFIS} = "NIL" if (! defined($$infos{AFIS}) && ($line =~ /AFIS : NIL/));
	  if (! defined($$infos{AA}) &&
	     (($line =~ /A\/A ?:? ?(\d{3}\.\d{1,3})/) || ($line =~ /A\/A ?:? ?\((\d{3}\.\d{1,3}) ?\)/) ||
		  ($line =~ /auto ?-? info ?:? (\d{3}\.\d{1,3})/i)))
	  {
	    $$infos{AA} = $1 if ($1 ne ".");
	  }

	  if (! defined($$infos{TWR}) &&
	     (($line =~ /TWR ?:? ?(\d{3}\.\d{1,3})/) || ($line =~ /TWR ?:? ?\((\d{3}\.\d{1,3})\)/) || ($line =~ /TWR :.*Tower (\d{3}\.\d{1,3})/)))
	  {
	    $$infos{TWR} = $1;
	  }

	  if (! defined($$infos{AFIS}) &&
	      (($line =~ /AFIS : ?(\d{3}\.\d{1,3})$/) || ($line =~ /AFIS : ?(\d{3}\.\d{1,3}) /) || ($line =~ /AFIS (\d{3}\.\d{1,3})$/) || ($line =~ /AFIS (\d{3}\.\d{1,3}) /) || 
		   ($line =~ /AFIS \((\d{3}\.\d{1,3})\)/) || ($line =~ /AFIS : .*? (\d{3}\.\d{1,3})$/) || ($line =~ /AFIS : .*? (\d{3}\.\d{1,3}) /)))
	  {
	    $$infos{AFIS} = $1;
	  }
	  
	  if (! defined($$infos{APP}) &&
	      ($line =~ /APP : .* Approach (\d{3}\.\d{1,3})$/))     #cas particulier LFAK
	  {
	    $$infos{APP} = $1;		  
	  }
	}  # fin de page 1

  }
  close FIC;

  my $frequence;
  if ((defined($$infos{AA})) && ($$infos{AA} ne "NIL"))
  {
	$frequence = $$infos{AA};
  }
  elsif ((defined($$infos{TWR})) && ($$infos{TWR} ne "NIL"))
  {
	$frequence = $$infos{TWR};
  }
  elsif ((defined($$infos{AFIS})) && ($$infos{AFIS} ne "NIL"))
  {
    $frequence = $$infos{AFIS};
  }
  elsif ((defined($$infos{APP})) && ($$infos{APP} ne "NIL"))
  {
    $frequence = $$infos{APP};
  }
  
  if (defined($frequence))    # on formate la fréquence en XXX.XXX, et on controle la fourchette
  {
    $frequence =~ s/\.$//;    # il y a parfois un point final en trop
	if (($frequence < 117) || ($frequence >= 138))
	{
	  print "$code. Frequence |$frequence| n'a pas une valeur correcte. On rejette\n" if ($verbose);
	  undef $frequence;
	}
	$frequence .= "00" if ($frequence =~ /^(\d{3}\.\d)$/);
	$frequence .= "0" if ($frequence =~ /^(\d{3}\.\d\d)$/);
  }

  if (!defined($frequence))
  {  
    if ((defined($$ADRef{frequence})) && ($$ADRef{frequence} ne ""))
    {
	  $frequence = $$ADRef{frequence};
	  print "$code. Frequence |$frequence| recuperee du fichier de reference\n" if ($verbose);
    }
    else
    {
	  print "$code. Frequence pas trouvee, ni dans le PDF, ni dans le fichier de reference\n" if ($verbose);
	}
  }
  if (defined($frequence))
  {
    $$infos{frequence} = $frequence;
	if ($frequence ne $$ADRef{frequence})
	{
	  print "$code. Frequence |$frequence| de carte VAC différente de fréquence |$$ADRef{frequence}| du fichier de reference\n" if ($verbose);

	}
  }

  $$infos{comment} = "$$infos{cat} $$infos{comment}";
}



  
sub getInfosFromOneVACfile_2
{
  my $code = shift;
  my $VACs = shift;
  my $ADRef = shift;
  my $cible = shift;
  my $infos = shift;
  my $fic = shift;
    
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
  
  my $start_qfu = 0;   # permet de savoir si on a atteint le moment des infos de type qfu, nature de terrain, ...
  my $missing_dim = 0; # pour rechercher dimension de la piste, quand ce n'est pas sur la meme ligne que les autres infos
  my $missing_nat = 0; # pou rechercher nature de la piste, quand ce n'est pas sur la meme ligne que les autres infos
  
  my $nblines = 0;
    
  while (my $line = <FIC>)
  {
	$nblines++;
	
    chomp ($line);
 	next if ($line eq "");

	################ pistes (qfu et dimension), nature ##################
	#print "$nblines, $start_qfu, $line\n";
	
	if (! $start_qfu)
	{
	  if ($line =~ /RWY +QFU? .*mension/)    #ligne de demarrage des infos qfu, dimension, nature
	  {
	    $start_qfu = $nblines;
	  }
	  next;                                  # pas la peine de chercher
	}
	
	if (! defined($$infos{qfu}))
	{
	  $line =~ s/\(1\) //;                   # ex : LFLP
		
	  if ($line =~ /^ *\d{1,2} ?[RLC]? +?(ACFT)? *?(\d{1,3})°? +?(\d{1,}) ?x ?\d{1,}(.*)/)
	  {
	    $$infos{qfu} = $2;
		$$infos{dimension} = $3;
		my $reste = $4;
		if ($reste =~ /(Revêtue|Non revêtue)/)
		{
		  $$infos{nature} = $1;
		}
	  }

	  elsif ($line =~ /^ *\d{1,2} ?[RL]? +?(\d{1,3})°? +?-? *(Revêtue|Non revêtue)/)   #ex : LFEN - LFHM
	  {
	    $$infos{qfu} = $1;
		$$infos{nature} = $2;
        $missing_dim = $nblines;		
	  }
	  
	  elsif ($line =~ /^ *\d{1,2} +?(\d{1,3})°? +?RWY +?\d/)   #ex : LFMC
	  {
	    $$infos{qfu} = $1;
        $missing_dim = $nblines;	
        $missing_nat = $nblines;		
	  }

	  elsif ($line =~ /^Omnidirectionnel/)                #ex : LFTB
	  {
	    $$infos{qfu} = "";
		$$infos{dimension} = "";
		$$infos{nature} = "eau";
      }
	  
	  next;
	}
	
	if ($missing_dim && ($line =~ /^ *\d{1,2} ?[RL]? *?(\d{1,3})°? +?(\d{1,})/))  # ex : LFEN - LFHM
	{
	  $$infos{dimension} = $2;
	}
	
	if ($missing_nat && ($line =~ /(Revêtue|Non revêtue)/))
	{
	  $$infos{nature} = $1;
	}
	
	last if ((defined($$infos{qfu})) && (defined($$infos{dimension})) && (defined($$infos{nature})));
	last if ($start_qfu && ($nblines > $start_qfu + 8));     # pas la peine d'aller plus loin
  }
  close FIC;
  
  if (defined($$infos{nature}))
  {
	if ($$infos{nature} eq "Revêtue") {$$infos{nature} = "dur"}
	elsif ($$infos{nature} eq "Non revêtue") {$$infos{nature} = "herbe"}
  }
    
}


#############################################################################
#              compareResultat
# utilisé en mode debug, si $debugFile est valué
# permet de comparer les resultats courants à ceux d'un fichier listVACfromPDF.csv précédent, et renommé
#############################################################################
sub compareResultat
{
  my $code = shift;
  my $infos = shift;
  my $fields = shift;
  
  if  (defined($debugFile))
  {

    foreach my $field (@$fields)
    {
      print "$code. $field |$$infos{$field}| de carte VAC différente de $field |$$debugADs{$code}{$field}| de l'ancien fichier\n"
	      	  if ($$infos{$field} ne $$debugADs{$code}{$field});
    }
  }	
}