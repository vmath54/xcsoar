#!/usr/bin/perl
#
# Lecture d'un fichier IGC
#
# voir l'entete de IGC.pm pour plus d'info

use IGC;
use Data::Dumper;

use strict;


{
  my $ficIGC = $ARGV[0];
  
  die "Il faut passer le nom d'un fichier IGC en argument" if ($ficIGC eq "");
  die "fichier $ficIGC n'existe pas" unless(-e $ficIGC);
  
  my $igc = new IGC();  
  $igc->read(file => $ficIGC);
  
  my $dateRecord = $igc->getHeaderByKey("DTE");
  print "date : $dateRecord\n"; 
 
  # my $records = $igc->getRecords(type => "B");
  # print Dumper($records);
  
  my $NMEAs = $igc->computeNMEA();  # transfo IGC -> NMEA
  foreach my $NMEA (@$NMEAs)
  {
    print "$NMEA\n";
  }
}
