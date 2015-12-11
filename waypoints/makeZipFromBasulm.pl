#!/usr/bin/perl
#
# creation de fichiers zip par region, avec les fichiers pdf issus de BASULM

use VAC;
use File::Basename;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Data::Dumper;

use strict;


my $dirFics  = "./basulm";  # le repertoire des fichiers pdf BASULM a inclure dans les fichiers zip
my $dirZip   = "basulm";    # le repertoire dans le .zip
my $ficREF      = "FranceVacEtUlm.cup";  # le fichier de reference. Permet de recupérer le département, et en déduire la région
                                         # les fichiers du répertoire qui ne sont pas dans le fichier de référence sont ignorés

my $verbose = 0;    # Si 1, indique les fichiers pdf qui ne sont pas references. Ce sont normalement des terrains fermés

### a adapter lorsque ca sera mieux defini
my $regions = 
{
  ACAL => { name => "Alsace Champagne Ardenne Lorraine", deps => ["08", "10", "51", "52", "54", "55", "57", "67", "68", "88" ] },
  ALPC  => { name => "Aquitaine Limousin Poitou Charentes", deps => ["16", "17", "19", "23", "24", "33", "40", "47", "64", "79", "86", "87" ] },
  ARA   => { name => "Auvergne Rhone-Alpes", deps => [ "01", "03", "07", "15", "26", "38", "42", "43", "63", "69", "73", "74" ] },
  BFC   => { name => "Bourgogne Franche-Comte", deps => [ "21", "25", "39", "58", "70", "71" ,"89", "90" ] },
  Br    => { name => "Bretagne", deps => [ "22", "29", "35", "56" ] },
  CVL   => { name => "Centre Val de Loire", deps => [ "18", "28", "36", "37", "41", "45" ] },
  Corse => { name => "Corse", deps => [ "20" ] },
  IDF   => { name => "Ile de France", deps => [ "75", "77", "78", "91", "92", "93", "94", "95" ] },
  LRMP  => { name => "Languedoc Roussillon Midi Pyrenees", deps => [ "09", "11", "12", "30", "31", "32", "34", "46", "48", "65", "66", "81", "82" ] },
  NPCP  => { name => "Nord Pas de Calais Picardie", deps => [ "02", "59", "60", "62", "80" ] },
  Norm  => { name => "Normandie", deps => [ "14", "27", "50", "61", "76" ] },
  PDL   => { name => "Pays de la Loire", deps => [ "44", "49", "53", "72", "85" ] },
  PACA  => { name => "Provence Alpes Cote d'Azur", deps => [ "04", "05", "06", "13", "83", "84" ] },
};
  
{
  my $deps = getDepartements();   # les regions, pour chaque departement
  my %zips = ();  # les fichier zip (par région) a creer
  my %ficsToArchive = ();  # les fichiers a zipper. 
  
  #### on récupère les infos de référence. En particulier, le département lié à un terrain  
  my $REFs = &readRefenceCupFile($ficREF);
  
  ####  on verifie que tout fichier PDF de $dirFics, connu du fichier de reference, a un departement dans ce fichier #####
  #     on en profite pour valuer %ficsToArchive
  
  my @fics = glob("$dirFics/*.pdf");
  foreach my $fic (@fics)
  {
    my $basename = basename($fic);
	die "$fic pas correct" unless ($basename =~ /(.*?)\.pdf$/);
	my $code = $1;
	if (! defined($$REFs{$code}))
	{
	  print "$code pas connu du fichier de reference\n" if ($verbose);
	  next;
	}
	next if ($$REFs{$code}{cible} ne "basulm");
	my $dep = $$REFs{$code}{depart};
	die "$code. pas trouve de departement dans fichier de reference" if ($dep eq "");
	
	my $region = $$deps{$dep};
	die "Pas de region connue pour le code |$code|, departement |$dep|" unless (defined($region));
	$ficsToArchive{$region}{$code} = {fic => $fic, code => $code };
  }
  
  #print Dumper(\%ficsToArchive); exit;
  #### maintenant, on ecrit les fichiers zip
  my $zip = Archive::Zip->new();
  {
    foreach my $region (keys %ficsToArchive)
	{
	  #next if ($region ne "IDF");
	  my $zip = Archive::Zip->new();
	  my $ficsRegion = $ficsToArchive{$region};
	  my $ficZip = "basulm_$region.zip";
      my $nbre = scalar(keys %$ficsRegion);
	  print "region = $region. $nbre terrains\n";

	  foreach my $code (sort keys %$ficsRegion)
	  {
	    my $fic = $$ficsRegion{$code}{fic};
		my $file_member = $zip->addFile($fic, "$dirZip/$code.pdf");
	    #print "$code => $fic\n";
	  }

      if ( $zip->writeToFileNamed($ficZip) == AZ_OK )
	  {
	    print "   Ecriture du fichier $ficZip\n";
	  }
	  else
	  {
	    die "probleme ecriture du fichier $ficZip";
	  }
	}
  }
}

#  retourne un hash departement => region
sub getDepartements
{
  my %deps = ();

  foreach my $region (keys %$regions)
  {
    my $Rdeps = $$regions{$region}{deps};
	foreach my $dep (@$Rdeps)
	{
	  $deps{$dep} = $region;
	}
  }
  return \%deps;
  #  pour verifier que tous les departements de metropole soient listes
  for (my $ind = 1; $ind <= 95; $ind++)
  {
    my $dep = sprintf ("%02d", $ind);
	die "departement |$dep| non trouve dans le hash des regions" unless (defined($deps{$dep}));
  }
  return \%deps;
}

