#!/usr/bin/perl
# -*- cperl -*-

use strict;
use utf8;
use open ':encoding(UTF-8)';
use open ":std";
use DateTime;
use Term::Size;
use Term::ReadKey;
use Time::HiRes qw(gettimeofday tv_interval);
use Term::ANSIColor;
use File::Spec::Functions qw(catfile);
use File::HomeDir;
use Math::Tau;
use Carp;

my $version = "0.2 alpha";

#################################################################################################
#################################################################################################
###
###                                        O P T I O N S :
###
#################################################################################################
#################################################################################################

my @clrdef = colordefs(); # Needed here because certain options base their enums on it.
my @clropt = map {  +{ key => $$_{key}, value => $$_{name}, name => $$_{name}, },
                  } grep { $$_{key} } @clrdef;
my @option = ( +{ short    => "-",
                  default  => undef,
                  true     => "true",
                  name     => "disable_shortops",
                  desc     => "When processing command-line arguments, ignore 'short-form' (hyphen-letter) options",
                  save     => "none",
                  # This is just in case somebody needs to do something bizarre,
                  # like specify a filename that starts with a hyphen, on the
                  # command line.  You can safely just ignore this option.
                },
               +{ name     => "localtimezone",
                  save     => "user",
                  default  => "America/New_York",
                  enum     => [ +{ key => "u", value => "UTC",                  name => "UTC", },
                                +{ key => "e", value => "America/New_York",     name => "Eastern", },
                                +{ key => "c", value => "America/Chicago",      name => "Central", },
                                +{ key => "m", value => "America/Denver",       name => "Mountain", },
                                +{ key => "p", value => "America/Los_Angeles",  name => "Pacific", },
                                +{ key => "k", value => "America/Anchorage",    name => "Alaska", },
                                +{ key => "q", value => "Europe/London",        name => "Britain", },
                                +{ key => "r", value => "Europe/Paris",         name => "Europe (CET)", },
                                +{ key => "s", value => "Europe/Helsinki",      name => "Europe (East)", },
                                +{ key => "t", value => "Europe/Moscow",        name => "Moscow", },
                                +{ key => "z", value => "Australia/Brisbane",   name => "Oz", },
                                +{ key => "n", value => "Pacific/Auckland",     name => "New Zealand", },
                              ],
                },
               +{ name    => "autosave",
                  default => "",
                  true    => "monthly",
                  desc    => "Automatically save your progress every so often.",
                  key     => "a",
                  save    => "user,game",
                  enum    => [ +{ key => "o", value => "", name => "off (F4 to save)", },
                               +{ key => "m", value => "monthly", name => "monthly",   },
                               +{ key => "a", value => "annually", name => "annually", },
                             ],
                },
               +{ name    => "colordepth",
                  default => 8,
                  true    => 24,
                  desc    => "Bit depth for terminal colors.",
                  key     => "c",
                  save    => "user",
                  enum    => [+{key => "a", value =>  4, name => "ANSI"},
                              +{key => "b", value =>  1, name => "Mono/bw"},
                              +{key => "c", value =>  8, name => "256-color"},
                              +{key => "d", value => 24, name => "TrueColor"},],
                },
               +{ name    => "focusbgcolor",
                  default => "blue",
                  desc    => "Background color used to indicate the currently focused frame.",
                  key     => "f",
                  save    => "user",
                  enum    => [+{ key => "v", value => "",        name => "various" },
                              @clropt,
                             ],
                },
               +{ name    => "delay",
                  short   => "d",
                  default => 1,
                  save    => "user",
                  regex   => qr/(\d+[.]?\d*)/,
                  desc    => "Number of seconds to let pass between iterations.  Does not have to be an integer.",
                },
               +{ name    => "xmax",
                  short   => "x",
                  default => 0,
                  desc    => "One less than the width of your terminal, in characters.  0 means use detected size.",
                  save     => "none",
                },
               +{ name    => "ymax",
                  short   => "y",
                  default => 0,
                  desc    => "One less than the height of your terminal, in characters.  0 means use detected size.",
                  save     => "none",
                },
               +{ name    => "nohome",
                  default => 0,
                  true    => 1,
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                  save    => "user",
                  desc    => "Instead of returning to home position before redrawing, just scroll the previous screenful out of the way.",
                },
               +{ name    => "fullrect",
                  default => 0,
                  true    => 1,
                  save    => "user",
                  desc    => "Go ahead and fill in the character in the very bottom-right corner of the screen.  (On some terminals, this can cause unwanted scrolling.)",
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                },
               +{ name    => "pauseonngp",
                  desc    => "Automatically pause the game when a new heir inherits.",
                  key     => "p",
                  default => "",
                  true    => "true",
                  save    => "user,game",
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                },
               +{ name    => "sellchickens",
                  desc    => "How to sell off spare chickens when necessary.",
                  key     => "s",
                  enum    => [+{ key => "b", value => "b", name => "best price",}, # Same in practice as good home, at least for now
                              +{ key => "g", value => "g", name => "good home",},
                              +{ key => "m", value => "m", name => "meat only",}, # Desirable once you start genetic engineering, as it protects trade secrets.
                             ],
                  default => "b",
                  save    => "game",
                },
               +{ name    => "savefile",
                  default => catfile(get_config_dir(), "eggs.save"),
                  desc    => "Path and file name of the saved-game file.",
                  save    => "none",
                },
               +{ name    => "optionsfile",
                  default => catfile(get_config_dir(), "eggs.cfg"),
                  desc    => "Path and file name of the user's options/configuration file.",
                  save    => "none",
                },
               +{ name    => "debug",
                  default => 0,
                  true    => 1,
                  save    => "none",
                },
               +{ name    => "channelcolor_story",
                  desc    => "Color for messages about the game's over-arching story and your character's life.",
                  default => "white",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_actioncancel",
                  desc    => "Color for messages about things you tried to do that didn't work out.",
                  default => "orange",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetloss",
                  desc    => "Color for messages about business losses you incur.",
                  default => "red",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetgain",
                  desc    => "Color for messages about things your business gains.",
                  default => "green",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetneed",
                  desc    => "Color for messages about things your business needs in order to grow.",
                  default => "orange",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_budgetaction",
                  desc    => "Color for messages about the results of your budget choices.",
                  default => "azure",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetsold",
                  desc    => "Color for messages about things your business sells; this includes things you have to sell for lack of space.",
                  default => "cyan",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_meta",
                  desc    => "Color for messages about matters external to the game itself (e.g., save/restore).",
                  default => "indigo",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_bug",
                  desc    => "Color for messages about programming errors you encounter in the game's implementation.  With any luck, maybe the chickens will eat all the bugs, and you'll never see these messages.  We can hope.",
                  default => "magenta",
                  save    => "user",
                  enum    => [ @clropt ],
                },
             );
my %opt = map { $$_{name} => $$_{default} } @option;
loadoptions(\%opt);

my @cmda = @ARGV; while (scalar @cmda) {
  my $x = shift @cmda;
  my $prevopt = undef;
  if (($x eq "--") and not $opt{disable_shortops}) {
    $opt{disable_shortops} = "true";
  } elsif ($x =~ /^-(\w+)$/ and not $opt{disable_shortops}) {
    for my $f (split //, $1) {
      my ($o) = grep { $$_{short} eq $f } @option;
      if ($o) {
        $opt{$$o{name}} = $opt{$$o{true}};
        $prevopt = $$o{name};
      } else {
        die "Unrecognized command-line option, -$f";
      }}
  } elsif ($x =~ /^--(\w+)=(.*)/) {
    my ($n, $v) = ($1, $2);
    my ($o) = grep { $$_{name} eq $n } @option;
    if ($o) {
      $opt{$$o{name}} = $v;
      $prevopt = undef;
    } else {
      die "Unrecognized command-line option, --$n";
    }
  } elsif ($x =~ /^--(\w+)$/) {
    my ($n) = ($1);
    my ($o) = grep { $$_{name} eq $n } @option;
    if ($o) {
      $opt{$$o{name}} = $$o{true};
      $prevopt = $$o{name};
    } else {
      die "Unrecognized command-line option, --$n";
    }
  } elsif ($prevopt) {
    $opt{$prevopt} = $x;
    $prevopt = undef;
  } else {
    die "Did not understand command-line option: $x";
  }
}

#################################################################################################
#################################################################################################
###
###                                    I N I T I A L I Z E :
###
#################################################################################################
#################################################################################################

my $reset = chr(27) . qq{[0m};
my ($screen, $xmax, $ymax, $wcount, $buyitem, $setting, $budgetitem, $debughint);
my ($wbg, $wtopbar, $wcashflow, $wmessages, $wassets, $wbudget, $wbuy, $wsettings,
    $wgameclock, $wrealclock,
    $wordkey, $wfocus, @widget);
my ($breedlvl, $genlvl, $genleak) = (1, 1, 1);

my (@message, @messageline);
my @relative = (["favourite uncle",  "he",  "his"],
                ["sainted aunt",     "she", "her"],
                ["grandfather",      "he",  "his"],
                ["grandmother",      "she", "her"],
                ((50 > rand 100) ? ["godfather", "he",  "his"] : ["godmother", "she", "her"]),
                (map {
                  ((50 > rand 100) ? [$_, "he", "his"] : [$_, "she", "her"]),
                } ("boss", "wealthy friend", "elderly neighbor", "second cousin", "English teacher", "classmate",
                   ((90 > rand 100) ? "secret admirer" : "creepy stalker"),
                   ((65 > rand 100) ? "grand" : "") . ((50 > rand 100) ? "father" : "mother") . "'s best friend",)),
                ["pastor",           "he",  "his"],
               );
#use Data::Dumper; print Dumper(+{ relative => \@relative }); exit 0;

my %cashflow;
my %globalkeybinding = global_key_bindings();
my $inputprefix = "";
my $now  = DateTime->now( time_zone => $opt{localtimezone} );
my $date = DateTime->new( year  => 1970,
                          month => 1,
                          day   => 1,
                          hour  => 6,
                        );
my ($cash, $runstarted, $ngpeta, $paused);
$cash = 0;
my (%buyqtty, %budget, %asset, %windowitem);

END { ReadMode 0; };
ReadMode 3;
$|=1;

debuglog("Started game session " . $now->ymd() . " at " . $now->hms());

%buyqtty = ( 1 => +{ id     => 1,
                     key    => "o",
                     name   => "one",
                     number => 1,
                     pmult  => 1,
                   },
             dose => +{ id     => "dose",
                        key    => "o",
                        name   => "one dose",
                        number => 1,
                        pmult  => 1,
                      },
             10 => +{ id     => 10,
                      key    => "t",
                      name   => "ten",
                      number => 10,
                      pmult  => 10,
                    },
             12 => +{ id     => 12,
                      key    => "d",
                      name   => "dozen",
                      number => 12,
                      pmult  => 11,
                    },
             dozendoses => +{ id     => "dozendoses",
                              key    => "d",
                              name   => "dozen doses",
                              number => 12,
                              pmult  => 11,
                            },
             100 => +{ id     => 100,
                       key    => "h",
                       name   => "hundred",
                       number => 100,
                       pmult  => 100,
                     },
             144 => +{ id     => 144,
                       key    => "g",
                       name   => "gross",
                       number => 144,
                       pmult  => 100,
                     },
             1728 => +{ id     => 1728,
                        key    => "l",
                        name   => "lot",
                        number => 1728,
                        pmult  => 1000,
                      },
             20736 => +{ id     => 20736,
                         number => 20736,
                         name   => "faireu",
                         key    => "f",
                         pmult  => 10000,
                       },
             feedbag => +{ id     => "feedbag",
                           key    => "b",
                           name   => "bag",
                           pmult  => 1, # feed prices are per-bag, of course
                           number => 150,
                           # A 25lb bag feeds one adult chicken for 150 days.
                           # Chicks eat less.
                         },
             feedpallet => +{ id     => "feedpallet",
                              key    => "p",
                              name   => "pallet",
                              pmult  => 24,
                              number => 3750,
                            },
             feedtruck => +{ id      => "feedtruck",
                             key     => "t",
                             name    => "truckload",
                             pmult   => 240,
                             number  => 45000,
                           },
             asneeded_feed => +{ id         => "asneeded_feed",
                                 key        => "a",
                                 name       => "as needed",
                                 number     => "asneeded",
                                 price      => "?",
                                 unlockqtty => 50000,
                               },
             asneeded => +{ id         => "asneeded",
                            key        => "a",
                            name       => "as needed",
                            number     => "asneeded",
                            price      => "?",
                            unlockqtty => 1728,
                          },
             cancel => +{ id         => "cancel",
                          key        => "c",
                          name       => "cancel",
                          number     => "cancel",
                          hilight    => "orange",
                          fg         => "yellow",
                          unlockqtty => "0 but true",
                        },
           );
my @pctopt = map { my ($pct, $key) = @$_;
                   +{ name  => $pct . '%',
                      key   => $key,
                      pct   => $pct,
                    }
                 } ((map { [ $_ => "$_" ] } 1 .. 6, 8),
                    ([ 10 => "t" ], [ 12 => "d" ], [ 15 => "f" ], [ 18 => "e" ]));

%budget = ( medexam => +{ id    => "medexam",
                          key   => "m",
                          name  => "medical examinations",
                          desc  => "Have a veterinarian examine your chickens.",
                          sort  => 1,
                          value => "off",
                          enum  => +[ +{ name         => "off",
                                         key          => "o",
                                         timesperyear => 0,
                                       },
                                      +{ name         => "yearly",
                                         key          => "y",
                                         timesperyear => 1,
                                       },
                                      +{ name         => "quarterly",
                                         key          => "q",
                                         timesperyear => 4,
                                       },
                                      +{ name         => "monthly",
                                         key          => "m",
                                         timesperyear => 12,
                                       },
                                    ],
                          budget => sub {
                            my ($foo) = @_;
                            $foo ||= $budget{medexam}{value};
                            my ($val) = grep { $$_{name} eq $foo } @{$budget{medexam}{enum}};
                            my $numofchickens = $asset{hen}{qtty} + $asset{rooster}{qtty} + $asset{chick}{qtty};
                            my $peryear = 300 * $$val{timesperyear} * $numofchickens;
                            # Budget is monthly, so that's 1/12th the annual, on average.
                            return int($peryear / 12);
                          },
                        },
            breeding => +{ id    => "breeding",
                           key   => "b",
                           name  => "breeding program",
                           desc  => "Devote a portion of your profits to breeding better chickens.",
                           sort  => 5,
                           value => 0,
                           enum  => +[ @pctopt ],
                           budget => sub {
                             my ($foo) = @_;
                             $foo ||= $budget{breeding}{value};
                             return $foo;
                           },
                         },
            genetics => +{ id     => "genetics",
                           key    => "g",
                           name   => "genetics research",
                           desc   => "Hire a geneticist to improve your chickens.",
                           sort   => 6,
                           value  => 0,
                           enum  => +[ @pctopt ],
                           unlock => 99999999,
                           budget => sub {
                             my ($foo) = @_;
                             $foo ||= $budget{genetics}{value};
                             return $foo;
                           },
                         },
            # TODO:
            #  * Lobbyists, who promote friendly legislation to increase prices on eggs and chicken meat.
          );
%asset   =  ( egg => +{ id     => "egg",
                        name   => "egg",
                        plural => "eggs",
                        desc   => "A fresh chicken egg is part of a balanced breakfast.",
                        value  => 4,
                        sort   => 1,
                        (map { $_ => 1 } qw(product egg)),
                      },
              dozen => +{ id      => "dozen",
                          name    => "dozen eggs",
                          plural  => "dozen eggs",
                          # Dimensions approximately 12" x 4" x 2.75"
                          desc    => "This carton contains one dozen fresh eggs.",
                          value   => 60,
                          sort    => 2,
                          (map { $_ => 1 } qw(product egg)),
                        },
              gross => +{ id     => "gross",
                          name   => "gross of eggs",
                          plural => "gross of eggs",
                          # Dimensions approximately 12" x 16" x 9"
                          desc   => "This case contains twelve dozen fresh eggs.",
                          value  => 850,
                          sort   => 3,
                          (map { $_ => 1 } qw(product egg)),
                        },
              palletload => { id     => "palletload",
                              name   => "pallet of eggs",
                              plural => "pallets of eggs",
                              # Dimensions 48" x 40" x 51", holds 6480 eggs.
                              # Holds 9 cases per layer (16 * 3 == 48; 12 * 3 == 36)
                              # Adds 6" to height, so five layers (5 * 9 == 45) + 6 == 51"
                              # 5 layers at 9 cases per layer == 45 gross, or 6480 eggs.
                              desc   => "This shipping pallet is stacked with 45 cases of fresh eggs.",
                              value  => 45000,
                              sort   => 4,
                              (map { $_ => 1 } qw(product egg)),
                            },
              containerload => { id     => "containerload",
                                 name   => "shipping container of eggs",
                                 plural => "containers of eggs",
                                 # Dimensions: 40' x 8' x 8'6".
                                 # Refrigerated.  Holds 24 pallets of eggs (12 rows of 2).
                                 desc   => "This shipping container holds 24 pallets of fresh eggs.",
                                 value  => 1200000,
                                 sort   => 5,
                                 (map { $_ => 1 } qw(product egg)),
                               },
              panamaxload => { id      => "panamaxload",
                               name    => "freighter loaded with eggs",
                               plural  => "freighters loaded with eggs",
                               # Dimensions: 1200' x 168' x 240' (50' draft, 190' above water).
                               # Holds 13000 TEU, i.e., 6500 of our 40' containers.
                               desc    => "This freighter is loaded with 6500 containers of fresh eggs.",
                               value   => 9000000000,
                               sort    => 6,
                               (map { $_ => 1 } qw(product egg)),
                             },
              podload => { id     => "podload",
                           name   => "cargo pod of eggs",
                           plural => "cargo pods of eggs",
                           desc   => "This cargo pod holds 1024 surface freighters of eggs fresh from Earth, a delicacy sure to arouse interest on any colony.",
                           value  => 12000000000000,
                           sort   => 7,
                         },
              chick => +{ id      => "chick",
                          name    => "baby chick",
                          desc    => "Baby chicks are cute.  They can grow up into hens or, sometimes, roosters.",
                          assetfg => "yellow",
                          value   => 60,
                          sort    => 100,
                          (map { $_ => 1 } qw(product good chicken)),
                          housein  => "nursery",
                          buyqtty  => [qw(1 12 144 1728 20736)],
                          unlocked => +{ buy => +{ 1 => 1, }, },
                          lifespan => +{ months => 7, }, # includes time to hatch;
                          # at EOL, a chick may grow up into a hen (or a rooster); this is handled by expire_asset()
                        },
              hen => +{ id           => "hen",
                        name         => "laying hen",
                        sellname     => "roasting hen",
                        sellplural   => "roasting hens",
                        assetfg      => "yellow",
                        desc         => "A good laying hen produces eggs on a regular basis.",
                        value        => 400,
                        sort         => 101,
                        (map { $_ => 1 } qw(product good chicken)),
                        housein      => "coop",
                        buyqtty      => [qw(1 12 144)],
                        unlocked     => +{ buy => +{ 1 => 1, }, },
                        lifespan     => +{ years => 8 },
                        needvitamins => "1970-01-31",
                      },
              rooster => +{ id         => "rooster",
                            name       => "rooster",
                            sellname   => "rooster for soup",
                            sellplural => "roosters for soup",
                            assetfg    => "red",
                            desc       => "With a rooster around, sometimes your hens will produce chicks.",
                            value      => 1200,
                            sort       => 102,
                            (map { $_ => 1 } qw(product good chicken)),
                            housein    => "coop",
                            buyqtty    => [qw(1 12 144)],
                            unlocked   => +{ buy => +{ 1 => 1, }, },
                            lifespan   => +{ years => 8 },
                          },
              chickenfeed => +{ id       => "chickenfeed",
                                name     => "chicken feed",
                                plural   => "chicken feed",
                                desc     => "Chickens have to eat.",
                                assetfg  => "cyan",
                                value    => 180, # That's per bag, not per serving.
                                sort     => 200,
                                (map { $_ => 1 } qw(supply good)),
                                buyqtty  => [qw(feedbag feedpallet feedtruck asneeded_feed)],
                                unlocked => +{ buy => +{ feedbag => 1, }, },
                              },
              vitamins => +{ id         => "vitamins",
                             name       => "vitamins",
                             plural     => "vitamins",
                             desc       => "Vitamins improve the health of your chickens.",
                             assetfg    => "cyan",
                             value      => 10, # That's an adult dose, per month; chicks use less.
                             sort       => 250,
                             (map { $_ => 1 } qw(supply good)),
                             buyqtty    => [qw(dose dozendoses 144 1728 20736 asneeded)],
                           },
              carton => +{ id      => "carton",
                           name    => "egg carton",
                           desc    => "Customers will pay more for your eggs if they are nicely packaged.  Holds one dozen.",
                           assetfg => "white",
                           buyqtty => [qw(1 12 144 1728 20736 asneeded)],
                           value   => 1,
                           sort    => 300,
                           (map { $_ => 1 } qw(good supply packaging)),
                         },
              case => +{ id      => "case",
                         name    => "egg case",
                         assetfg => "white",
                         desc    => "Stores will pay more for your eggs if they are neatly packaged.  Holds 12 cartons.",
                         value   => 5,
                         sort    => 301,
                         buyqtty => [qw(1 12 144 1728 asneeded)],
                         (map { $_ => 1 } qw(good supply packaging)),
                       },
              emptypallet => +{ id      => "emptypallet",
                                name    => "pallet",
                                assetfg => "white",
                                desc    => "Supermarkets will pay more for your eggs if they are nicely palleted up for delivery.  Holds 45 cases.",
                                value   => 100,
                                sort    => 302,
                                buyqtty => [qw(1 12 144 asneeded)],
                                (map { $_ => 1 } qw(good supply packaging)),
                              },
              emptycontainer => +{ id      => "emptycontainer",
                                   name    => "shipping container (rental)",
                                   desc    => "Distributors charge less to deliver your eggs if they are packed in standard intermodal shipping containers.  Holds 24 pallets.",
                                   value   => 20000,
                                   sort    => 303,
                                   assetfg => "grey",
                                   buyqtty => [qw(1 12 144 asneeded)],
                                   (map { $_ => 1 } qw(good supply packaging)),
                                 },
              emptyfreighter => +{ id      => "emptyfreighter",
                                   name    => "panamax freighter (rental)",
                                   desc    => "Loading your eggs onto a freighter allows you to sell them to international markets, which pay a higher price than the domestic market.  This freighter is designed for the new locks, so it holds 6500 forty-foot shipping containers (1300 TEU).",
                                   sort    => 304,
                                   assetfg => "grey",
                                   value   => 120000000,
                                   buyqtty => [qw(1 12 144 asneeded)],
                                   (map { $_ => 1 } qw(good supply packaging)),
                                 },
              emptypod => +{ id      => "emptypod",
                             name    => "cargo pod (rental)",
                             desc    => "Packing your eggs in a standard cargo pod lets you sell them all around the solar system.  Holds 1024 terrestrial shipping containers.",
                             assetfg => "grey",
                             sort    => 305,
                             value   => 200000000000,
                             buyqtty => [qw(1 12 144 asneeded)],
                             (map { $_ => 1 } qw(good supply packaging)),
                           },
              coop => +{ id       => "coop",
                         name     => "chicken coop",
                         desc     => "Holds up to 30 chickens.  Takes up 300 square feet on your land.",
                         capacity => 30,
                         value    => 500000,
                         landsize => 300,
                         sort     => 550,
                         assetfg  => "brown",
                         buyqtty  => [qw(1 10 100 asneeded)],
                         (map { $_ => 1 } qw(good housing)),
                       },
              nursery => +{ id        => "nursery",
                            name      => "chick nursery",
                            desc      => "Holds up to 300 chicks.  Takes up 20 square feet on your land.",
                            sort      => 500,
                            capacity  => 300,
                            landsize  => 20,
                            value     => 15000,
                            assetfg   => "brown",
                            buyqtty   => [qw(1 10 100 asneeded)],
                            (map { $_ => 1 } qw(good housing)),
                          },
              acre => +{ id       => "acre",
                         name     => "acre of land",
                         plural   => "acres of land",
                         desc     => "Land, on which you can build things, such as chicken coops.",
                         value    => 10000000,
                         sort     => 700,
                         assetfg  => "green",
                         buyqtty  => [qw(1 10 100 asneeded)],
                         (map { $_ => 1 } qw(good housing)),
                         # An acre is nominally 43560 square feet, but you can't actually use quite 100%
                         # of that in practice, because among other things you can't build right at the
                         # edge, and you need paths between the buildings.  For simplicity, we'll say
                         # that an acre can support forty thousand square feet of buildings.
                         capacity => 40000,
                       },
              # TODO:
              #  * Licenses that allow you to operate in more jurisdictions, increasing the # of acres you can own.
              #  * Feed plants, which produce chicken feed for you, so you don't have to buy it all.
              #  *
            );

our @breedmsg = (undef,
                 qq[Your breeding program has produced healthier chickens.], # This is the default message, for levels that don't provide a specific effect.
                 # TODO: certain breed levels should provide specific effects.
                );
our @genmsg = (undef,
               qq[Your geneticists have produced better chickens.], # Default message for most genlvl values.
               # TODO: certain genetic levels should provide more specific effects.
              );

%windowitem = init_windowitems();
ngp();

if (-e ($opt{savefile} || catfile(get_config_dir(), "eggs.save"))) {
  restoregame();
}
push @message, ["Press F1 for help.", "help"];
refreshscreen();

#################################################################################################
#################################################################################################
###
###                                     M A I N    L O O P :
###
#################################################################################################
#################################################################################################

while (1) {
  iterate() unless $paused; # Do the egg-game-specific once-per-turn things.
  for my $w (@widget) {
    if (not $$w{__INTERVAL_POS__}) {
      dowidget($w, $screen);
      $$w{__INTERVAL_POS__} = $$w{interval};
    } else {
      redraw_widget($w, $screen);
    }
    $$w{__INTERVAL_POS__} = $$w{__INTERVAL_POS__} - 1 if $$w{interval};
  }
  updatetopbar($wtopbar);
  drawscreen($screen);
  my $delay = $opt{delay} || 1;
  while ($delay > 0) {
    my $since = [gettimeofday()];
    my $key = ReadKey($delay);
    process_key($key) if defined $key;
    my $ival = tv_interval($since);
    $delay -= $ival;
  }
}
exit 0; # Can't Happen
# Subroutines follow...


#################################################################################################
#################################################################################################
###
###                                E G G    G A M E    L O G I C :
###
#################################################################################################
#################################################################################################

sub ngp {
  my $relative = $relative[0]; @relative = randomorder(@relative);
  #use Data::Dumper; print Dumper(+{ "relatives" => \@relative, chosen_relative => $relative, });
  my ($noun, $pronoun, $possessive) = @$relative;
  my $feed = int(($asset{chickenfeed}{qtty} || 4) / 4); $feed = 4320 if $feed < 4320;
  my $nurs = int(($asset{nursery}{qtty} || 1) / ($asset{coop}{qtty} || 1)); $nurs = 1 if $nurs < 1;
  my $acre = int(log(($asset{acre}{qtty} || 1)) / log(tau)); $acre = 1 if $acre < 1;
  my $vita = int($asset{vitamins}{qtty} / 4);
  my $coop = int($asset{coop}{qtty} / 4) || 1;
  # TODO: enough licenses to cover that acreage.
  @message  = (["So there you are, penniless and fresh out of school, wondering what you're going to do now, and it seems your $noun has just died; and $pronoun left you "
                . (($acre == 1) ? "an acre" : shownum($acre) . " acres") . " of land, with "
                . (($coop == 1) ? "a chicken coop" : shownum($coop)) . " chicken coops"
                . " on it, and $possessive best laying hen.  ", "story"]);
  @messageline = ();
  rewrap_message_log();
  %cashflow = map { $_ => +{} } qw(current lastmonth year lastyear total);
  $cash = 0;
  $runstarted = $date;
  $ngpeta     = $runstarted->clone()->add(years => 40 + int rand 40, days => 1 + int rand 365 );

  my %keepasneeded = map { $_ => 1 } qw(chickenfeed
                                        carton case emptypallet emptycontainer emptyfreighter emptypod
                                        acre); # TODO: licenses?
  # I had to take vitamins off the keep-as-needed list because
  # sometimes they ran out when there happened to be enough cash on
  # hand to buy an unnecessarily large quantity of them, but that
  # money was needed for food.  This resulted in starving chickens.
  for my $k (keys %asset) {
    $asset{$k}{qtty} = 0;
    $asset{$k}{agegroup} = +[];
    $asset{$k}{asneeded} = undef unless $keepasneeded{$k};
    # Unlocked things stay unlocked.
  }
  addasset("hen", 1);
  addasset("chickenfeed", $feed);
  addasset("coop", $coop);
  addasset("nursery", $nurs);
  addasset("acre", $acre);
  # TODO: licenses and such
  if ($opt{pauseonngp}) {
    toggle_pause("force_pause_on");
  }
}

sub iterate {
  my ($ival) = @_;
  $ival ||= "days"; # I was originally thinking to allow the user to unlock the ability to set this to
                    # weeks, months, maybe even years; but eventually I thought better of it.  If the
                    # user needs to let huge amounts of time pass quickly, it's a sign that the pace of
                    # progress or development has slowed too much, and that should be addressed instead.
  my $dt = $date->clone();
  $date = $date->add($ival => 1);
  #$$wgameclock{faketime} = $date;
  my $days = 0;
  while ($dt->ymd() lt $date->ymd()) {
    $dt = $dt->add(days => 1);
    $days++;
  }
  if ($ngpeta->ymd() lt $date->ymd()) {
    if ($asset{hen}{qtty} < 1) {
      print $reset . gotoxy(0,0)
        . chr(27) . "[2J" # clear-screen
        . gotoxy(0,0)
        . $reset . "Your will calls for your best prize laying hen to be left to your heir.\nUnfortunately, you no longer have that hen.\nYour will is tied up in probate for decades, and your heir never gets into the egg business.\n\n";
      unlink $opt{savefile} unless $opt{debug};
      exit 0;
    }
    ngp();
  }
  if (($asset{vitamins}{qtty} > 0) or ($asset{vitamins}{asneeded})) {
    for my $chickentype (grep { $asset{$_}{qtty} > 0 } qw(hen rooster chick)) {
      $asset{$chickentype}{needvitamins} ||= $date->ymd();
      if ($asset{$chickentype}{needvitamins} le $date->ymd()) {
        my $dosesneeded = ($chickentype eq "chick")
          ? int(($asset{$chickentype}{qtty} + 9) / 10)
          : $asset{$chickentype}{qtty};
        if (($asset{vitamins}{qtty} < $dosesneeded) and
            ($asset{vitamins}{asneeded})) {
          buyatleast("vitamins", $dosesneeded - $asset{vitamins}{qtty}, "need");
        }
        if ($asset{vitamins}{qtty} >= $dosesneeded) {
          my $nextmonth = $date->clone()->add(days => 30);
          $asset{vitamins}{qtty} -= $dosesneeded;
          $asset{$chickentype}{needvitamins} = $nextmonth->ymd();
        }}}} else {
          $asset{vitamins}{unlocked}{buy}{dose} ||= 1;
        }
  if ($date->mday() == 1) {
    update_levels();
    monthly_expenses();
    savegame() if $opt{autosave} eq "monthly";
    if ($opt{debug}) {
      use Data::Dumper;
      debuglog("Cashflow: " . Dumper(\%cashflow, +{ year  => $date->year(),
                                                    month => $date->month(),
                                                    mday  => $date->mday()}));
    }
    $cashflow{lastmonth} = $cashflow{current};
    $cashflow{current} = +{};
    $cashflow{sc}{lastmonth} = $cashflow{sc}{current};
    $cashflow{sc}{current} = +{};
    if ($date->month() == 1) {
      $cashflow{lastyear} = $cashflow{year};
      $cashflow{year} = +{};
      $cashflow{sc}{lastyear} = $cashflow{sc}{year};
      $cashflow{sc}{year} = +{};
      savegame() if $opt{autosave} eq "annually";
    }
  }
  my $mealsneeded = $days * int($asset{hen}{qtty} + $asset{rooster}{qtty} + (($asset{chick}{qtty} + 3) / 7));
  $asset{chickenfeed}{qtty} -= $mealsneeded;
  debuglog("chickenfeed: $asset{chickenfeed}{qtty}");
  if (($asset{chickenfeed}{qtty} <= 0) and ($asset{chickenfeed}{asneeded})) {
    buyatleast("chickenfeed", $mealsneeded, "need");
  }
  if ($asset{chickenfeed}{qtty} + ($mealsneeded / 2) < 0) {
    for my $x (["hen"     => int(valuefromexpectations(12, $asset{hen}{qtty}))],
               ["rooster" => int(valuefromexpectations(15, $asset{rooster}{qtty}))],
               ["chick"   => int(valuefromexpectations(30, $asset{chick}{qtty}))],
              ) {
      my ($atype, $numdead, $degrouped) = @$x;
      debuglog("Starvation cycle: $atype, $numdead");
      # We take the oldest ones first.  This is merciful to the player
      # when doing adult chickens, less so when doing chicks, but in
      # any case it's _simplest_, because we can just process groups
      # in the order in which they were added, i.e., oldest first.
      for my $group (@{$asset{$atype}{agegroup} || +[]}) {
        my $kill = $numdead - $degrouped;
        $kill = $$group{qtty} if $kill > $$group{qtty};
        $$group{qtty} -= $kill;
        $asset{$atype}{qtty} -= $kill;
        $degrouped += $kill;
      }
      $asset{$atype}{agegroup} = [grep { $$_{qtty} > 0 } @{$asset{$atype}{agegroup}}];
      push @message, [$degrouped . " " . sgorpl($degrouped, $asset{$atype}{name}) . " starved.", "assetloss"]
        if $degrouped > 0;
    }
  }
  $asset{chickenfeed}{qtty} = 0 if $asset{chickenfeed}{qtty} < 0;
  my $laid = int(valuefromexpectations(chicken_health_ev(60, "hen", "laying"),
                                       $asset{hen}{qtty}));
  if ($asset{rooster}{qtty} > 0) {
    # Convert some of the eggs into chicks:
    my $mayconvert = int ($laid / 10);
    if ($mayconvert == 0) {
      $mayconvert = 1 if (($laid * 10) > rand 100);
    }
    if ($mayconvert > 0) {
      my $max = 10 * $asset{rooster}{qtty} + rand(10 * $asset{rooster}{qtty});
      $max = $mayconvert if $max > $mayconvert;
      $max = 1 if (($max < 1) and ($asset{rooster}{qtty} > 0));
      my $chicks = valuefromexpectations(chicken_health_ev(25, "rooster", "fertilization"), $max);
      if ($chicks > 0) {
        $laid -= $chicks;
        # This message gets way too spammy.  Maybe aggregate it per month?
        #push @message, [shownum($chicks) . " " . sgorpl($chicks, "baby chick")
        #                . " " . isare($chicks). " born.",
        #                "assetgain"];
        my $keepchicks = $chicks;
        my $soldchicks = 0;
        while ($keepchicks and not canhouse($keepchicks, "nursery")) {
          # Sell off excess chicks if there isn't enough nursery space.
          my $sell = ($keepchicks < 10) ? 1 : int($keepchicks / 2);
          my $per  = ($opt{sellchickens} eq "m") ? 1 : ($asset{chick}{value} / 2);
          my $price = int($sell * $per);
          gaincash($price, "sales", "chicks");
          $keepchicks -= $sell;
          $soldchicks += $sell;
          # If selling live chicks, your competitors get any genetic enhancements you've got.
          if (($sell > 0) and ($opt{sellchickens} ne "m")) {
            $genleak = $genlvl if $genleak < $genlvl;
          }
        }
        $asset{nursery}{unlocked}{buy}{1} ||= 1 if $soldchicks;
        push @message, ["Sold " . shownum($soldchicks) . " " .
                        sgorpl($soldchicks, (($opt{sellchickens} eq "m") ? "chick nugget" : "chick"))
                        . ".", "assetsold"]
          if $soldchicks;
        addasset("chick", $keepchicks) if $keepchicks;
      }
    }
  }
  $asset{egg}{qtty} += $laid;
  for my $grouping ([ 12,   "egg", "dozen", "carton"],
                    [ 12,   "dozen", "gross", "case"],
                    [ 45,   "gross", "palletload", "emptypallet", ],
                    [ 24,   "palletload", "containerload", "emptycontainer" ],
                    [ 6500, "containerload", "panamaxload", "emptyfreighter" ],
                    [ 1024, "panamaxload", "podload", "emptypod", ],
                   ) {
    my ($per, $item, $group, $container) = @$grouping;
    my $n = int($asset{$item}{qtty} / $per);
    if ($asset{$container}{qtty} < $n) {
      if ($asset{$container}{asneeded}) {
        my $containersneeded = $n - $asset{$container}{qtty};
        buyatleast($container, $containersneeded, "need");
      } else {
        $asset{$container}{unlocked}{buy}{1} ||= 1;
      }
      $n = $asset{$container}{qtty} if $n > $asset{$container}{qtty};
    }
    if ($asset{$container}{qtty} >= $n) {
      $asset{$container}{qtty} -= $n;
      $asset{$item}{qtty}      -= $n * $per;
      $asset{$group}{qtty}     += $n;
      debuglog("Grouped " . $n * $per . " of $item into $n of $container.")
        if $opt{debug} > 5;
    } else {
      debuglog("Failed to group " . $n * $per . " of $item into $n of $container.");
    }
  }
  my $sellunit = "egg";
  for my $u (qw(dozen gross paletteload containerload)) {
    if ($asset{$u}{qtty} > 0) {
      $sellunit = $u;
    }}
  my $newmoney = $asset{$sellunit}{value} * $asset{$sellunit}{qtty};
  $asset{$sellunit}{qtty} = 0;
  gaincash($newmoney, "sales", "eggs");
  # Things age over time:
  for my $atype (grep { $asset{$_}{lifespan} } keys %asset) {
    for my $grp (@{$asset{$atype}{agegroup}}) {
      if ($$grp{expire} le $date->ymd()) {
        expire_asset($atype, $$grp{qtty});
        $$grp{qtty} = 0;
      }}
    $asset{$atype}{agegroup} = [grep { $$_{qtty} } @{$asset{$atype}{agegroup}}];
  }
}

sub update_levels {
  # Breeding program: any results yet?
  my $blvl = int(log(1 + int($cashflow{sc}{total}{budget}{$budget{breeding}{name}} / 1000)));
  if ($blvl > $breedlvl) {
    push @message, [$breedmsg[$blvl] || $breedmsg[1], "budgetaction"];
    $breedlvl = $blvl;
  }
  my $glvl = int(log(1 + int($cashflow{sc}{total}{budget}{$budget{genetics}{name}} / 100000)));
  if ($glvl > $genlvl) {
    push @message, [$genmsg[$glvl] || $genmsg[1], "budgetaction"];
    $genlvl = $glvl;
  }
}

sub monthly_expenses {
  my ($examsetting) = grep { $$_{name} eq $budget{medexam}{value} } @{$budget{medexam}{enum}};
  if (($$examsetting{timesperyear} > 0) and not ($date->month() % $$examsetting{timesperyear})) {
    my $numofchickens = $asset{hen}{qtty} + $asset{rooster}{qtty} + $asset{chick}{qtty};
    if ($numofchickens > 0) {
      my $examscost   = 300 * $numofchickens;
      expendcash($examscost, "budget", "medical exams");
      for my $ctype (qw(hen rooster chick)) {
        $asset{$ctype}{examined} = $date->ymd();
      }
      push @message, [(($numofchickens == 1) ? "Your chicken" :
                       ($numofchickens == 2) ? "Both of your chickens" : "All of your chickens")
                      . " receive medical " . sgorpl($numofchickens, "examination") . ".", "budgetaction"];
    }}
}

sub expire_asset {
  my ($atype, $qtty) = @_;
  my $ustahav = $asset{$atype}{qtty};
  $asset{$atype}{qtty} -= $qtty;
  if ($asset{$atype}{qtty} < 0) { $asset{$atype}{qtty} = 0; }
  my %sold;
  if ($atype eq "chick") {
    my $hens = valuefromexpectations(chicken_health_ev(65, "chick", "hen"), $qtty);
    $hens = $qtty if $hens > $qtty;
    my $remaining = $qtty - $hens;
    if ($hens > 0) {
      my $keephens = $hens;
      while ($keephens and not canhouse($keephens, "coop")) {
        # Sell off excess hens.  You don't get full value.  If selling
        # off at best price or to a good home, your competitors
        # benefit from genetic enhancements you've created.
        my $sell = ($keephens < 10) ? 1 : int($keephens / 2);
        my $per  = ($opt{sellchickens} eq "m")
          ? ($asset{hen}{value} / 3)
          : ($asset{hen}{value} / 2);
        my $price = int($sell * $per);
        gaincash($price, "sales", "hens");
        $keephens -= $sell;
        $sold{hen} += $sell if $sell > 0;
      }
      addasset("hen", $keephens) if $keephens > 0;
      push @message, [shownum($hens) . " " . sgorpl($hens, "chick")
                      . " grew up into " . sgorpl($hens, "a hen", "hens") . ".", "assetgain"];
    }
    if ($remaining > 0) {
      my $roosters = valuefromexpectations(chicken_health_ev(25, "chick", "rooster"), $remaining);
      $roosters = $remaining if $roosters > $remaining;
      if ($roosters > 0) {
        push @message, [shownum($roosters) . " " . sgorpl($roosters, "chick")
                        . " grew up into " . sgorpl($roosters, "a rooster", "roosters") . ".", "assetgain"];
        my $keeproosters = $roosters;
        while ($keeproosters and not canhouse($keeproosters, "coop")) {
          # Sell off excess roosters.  You don't get full value.
          my $sell = ($keeproosters < 10) ? $keeproosters : int($keeproosters / 2);
          my $per  = ($opt{sellchickens} eq "m")
            ? ($asset{hen}{value} / 4) # For meat, roosters are actually worth _less_ than hens.  Tougher meat, only good for soup.
            : ($asset{rooster}{value} / 2);
          my $price = int($sell * $per);
          gaincash($price, "sales", "roosters");
          $keeproosters -= $sell;
          $sold{rooster} += $sell if $sell > 0;
        }
        addasset("rooster", $keeproosters) if $keeproosters > 0;
      }
      if ($remaining > $roosters) {
        my $died = $remaining - $roosters;
        if (($asset{$atype}{qtty} == 0) and ($hens == 0) and ($roosters == 0)) {
          push @message, ["Your " . sgorpl($qtty, "chick") . " died :-(", "assetloss"];
        } else {
          push @message, [shownum($died) . " " . sgorpl($died, "chick") . " died.", "assetloss"];
        }
      }
    }
  } elsif (($atype eq "hen") or ($atype eq "rooster")) {
    if (($atype eq "hen") and ($asset{hen}{qtty} == 0)) {
      addasset("hen", 1); # Don't let the player's last laying hen die of old age.
    }
    my $died = $ustahav - $asset{$atype}{qtty};
    push @message, [$died . " " . sgorpl($died, $asset{$atype}{name},
                                         $asset{$atype}{plural}) . " died.", "assetloss"]
      if $died > 0;
  } else {
    push @message, ["Error: unanticipated asset expiration: '$atype'.", "bug"];
  }
  if (keys %sold) {
    debuglog("coop unlock " . $asset{coop}{unlocked}{buy}{1}++);
    if ($opt{sellchickens} ne "m") {
      $genleak++ if (($genleak < $genlvl) and ( 5 > rand 100));
    }
    push @message, ["Sold " . (commalist(map {
      my $atype = $_;
      my $sname = ($opt{sellchickens} eq "m")
        ? ($asset{$atype}{sellname} || $asset{$atype}{name})
        : $asset{$atype}{name};
      my $splur = ($opt{sellchickens} eq "m")
        ? ($asset{$atype}{sellplural} || $asset{$atype}{plural})
        : $asset{$atype}{plural};
      shownum($sold{$atype}) . " " . sgorpl($sold{$atype}, $sname, $splur);
    } sort {
      $asset{$a}{value} <=> $asset{$b}{value}
    } keys %sold) . "."), "assetsold"];
  }
}

sub chicken_health_ev {
  my ($baseev, $ctype, $reason) = @_;
  my $ev = $baseev;
  my %multiplier = chicken_health_modifiers($ctype, $reason);
  for my $mk (keys %multiplier) {
    $ev = int($ev * $multiplier{$mk});
  }
  return $ev;
}

sub chicken_health_modifiers {
  my ($ctype, $reason) = @_;
  my %mod = ( vitamins => (($asset{$ctype}{needvitamins} ge $date->ymd())
                           ? 1.1
                           : 1),
              # TODO: immunizations
              breeding => (1 + ($breedlvl / 50)),
            );
  my %genrelevant = map { $_ => 1 } qw(laying fertilization);
  if ($genrelevant{$reason}) {
    $mod{genetics} = (1 + ($genlvl / 50));
  }
  return %mod;
}

sub safetobuy {
  my ($atype, $number) = @_;
  debuglog("safetobuy($atype, $number);");
  if ($asset{$atype}{chicken}) {
    #$asset{$asset{$atype}{housein}}{unlocked}{buy}{1} ||= 1
    #  if $asset{$atype}{qtty} >= ($asset{$asset{$atype}{housein}}{capacity} * 4 / 5);
    debuglog(" stb: returning canhouse($number, $asset{$atype}{housein})");
    return canhouse($number, $asset{$atype}{housein});
  } elsif ($asset{$atype}{landsize}) {
    debuglog(" stb: returning canbuild($number, $atype)");
    return canbuild($number, $atype);
  } # TODO: licenses and such will have other criteria.
  debuglog(" stb: returning $number");
  return $number;
}

sub canhouse {
  my ($n, $housingtype) = @_;
  # Can we house $n _additional_ chickens in our coops (or chicks in our nurseries)?
  debuglog("canhouse($n, $housingtype)");
  if (not $n) {
    if ($opt{debug}) { croak "canhouse(0, $housingtype)"; }
    return; # No infinite loops pls, kthx.
  }
  my $capacity = $asset{$housingtype}{qtty} * $asset{$housingtype}{capacity};
  my $left = $capacity - (($housingtype eq "nursery") ? $asset{chick}{qtty} : ($asset{hen}{qtty} + $asset{rooster}{qtty}));
  my $needed = 0;
  debuglog(" ch: n=$n; ht=$housingtype; cap=$capacity; left=$left; needed=$needed");
  while ($left < $n) {
    # TODO: This takes O(n) time; write an O(1) formula for it.
    $needed++; $left += $asset{$housingtype}{capacity};
  }
  debuglog(" ch: n=$n; ht=$housingtype; cap=$capacity; left=$left; needed=$needed");
  # Simple case: if we already have the capacity, we're good:
  if ($needed == 0) {
    debuglog(" ch: returning $n");
    return $n;
  }
  # Failing that, can we autobuy the housing?
  my $value = $asset{$housingtype}{value} * $needed;
  debuglog(" ch: value=$value (and cash=$cash)");
  return if ($value > $cash); # Cannot afford.
  if (not $asset{$housingtype}{asneeded}) {
    debuglog(" ch: cannot buy as needed");
    # We aren't buying as-needed, but make sure buying is unlocked:
    if (not $asset{$housingtype}{unlocked}{buy}{1}) {
      debuglog(" ch: unlocking manual buy for $housingtype");
      $asset{$housingtype}{unlocked}{buy}{1}++;
      push @message, ["You need more " . sgorpl(3, $asset{$housingtype}{name},
                                            $asset{$housingtype}{plural}) . ".", "assetneed"];
    }
    return;
  }
  if (canbuild($needed, $housingtype)) {
    debuglog(" ch: cb sez ok, rechecking cash ($cash) against value ($value)");
    return if $value > $cash; # In case buying the housing used up our funding.
    debuglog(" ch: building $needed $housingtype");
    buyasset($housingtype, $needed, $value, "canhouse");
    debuglog(" ch: returning $n");
    return $n;
  } else {
    debuglog(" ch: cb sez no.");
    return;
  }
}

sub canbuild {
  # Do we have enough space on our land to build these things?
  my ($number, $assetid) = @_;
  my $needland = $asset{$assetid}{size} * $number;
  my $usedland = 0;
  for my $atype (grep { $asset{$_}{landsize} } keys %asset) {
    $usedland += $asset{$atype}{qtty} * $asset{$atype}{landsize};
  }
  my $haveland = $asset{acre}{qtty} * $asset{acre}{capacity};
  if ($usedland + $needland <= $haveland) {
    return $number; # Yep, got it covered.
  }
  # Don't have enough acreage.  Can we autobuy enough?
  my $acresneeded = 0;
  while ($usedland + $needland <= $haveland + ($acresneeded * $asset{acre}{capacity})) {
    # TODO: This takes O(n) time; write an O(1) formula for it.
    $acresneeded++;
  }
  my $value = $acresneeded * $asset{acre}{value};
  return if $cash < $value;
  if (not $asset{acre}{asneeded}) {
    # We aren't buying land as needed, but ensure buying it is unlocked:
    if (not $asset{acre}{unlocked}{buy}{1}) {
      $asset{acre}{unlocked}{buy}{1}++;
      push @message, ["You need more land to build on.", "assetneed"];
    }
  }
  # TODO: check licenses.
  buyasset("acre", $acresneeded, $value, "canbuild");
  return $number;
  return;
}

##sub asset_cost {
##  my ($atype, $number) = @_;
##  my $total = 0;
##  my $stillneed = $number;
##  for my $q (reverse grep { $buyqtty{$_}{pmult}
##                          } (grep {
##                            $asset{$atype}{unlocked}{buy}{$_}
##                          } @{$asset{$atype}{buyqtty} || [1]})) {
##    my $n = int($stillneed / $buyqtty{$q}{number});
##    $total       += $n * $buyqtty{$q}{pmult} * $asset{$atype}{value};
##    $stillneeded -= $n * $buyqtty{$q}{number};
##  }
##  return $total;
##}

sub buyatleast { # If adequate funds are available, that is.
  my ($atype, $min, $blame) = @_;
  debuglog("buyatleast($atype, $min);");
  my $purchased = 0;
  my $stillneed = $min;
  for my $q (reverse grep { $buyqtty{$_}{pmult}
                          } (grep {
                            $asset{$atype}{unlocked}{buy}{$_}
                          } @{$asset{$atype}{buyqtty} || [1]})) {
    if ($stillneed > 0) {
      my $n = int($stillneed / $buyqtty{$q}{number});
      if ($n * $buyqtty{$q}{number} < $stillneed) { $n++; }
      my $price = $n * $buyqtty{$q}{pmult} * $asset{$atype}{value};
      debuglog(" bal: q=$q; n=$n; p=$price; c=$cash");
      if ($price < $cash) {
        debuglog(" bal: attempting to buy " . ($n * $buyqtty{$q}{number}) . ".");
        buyasset($atype, $n * $buyqtty{$q}{number}, $price, $blame);
        $purchased += $n * $buyqtty{$q}{number};
        $stillneed -= $n * $buyqtty{$q}{number};
      } else {
        debuglog(" bal: no can do, $price < $cash");
      }
    }
  }
  debuglog(" bal: fell short by $stillneed") if $stillneed > 0;
  return $purchased;
}

sub buyasset {
  my ($item, $number, $value, $blame) = @_;
  debuglog("buyasset($item, $number, $value);");
  return if ($value > $cash);
  expendcash($value, (($blame eq "need") ? "essentials" : "purchases"),
             $asset{$item}{plural} || makeplural($asset{$item}{name}));
  addasset($item, $number);
  if (ref $asset{$item}{buyqtty}) {
    for my $q (@{$asset{$item}{buyqtty}}) {
      my $unlockat = $buyqtty{$q}{unlockqtty} || $buyqtty{$q}{number};
      if ($asset{$item}{qtty} >= $unlockat) {
        if ($buyqtty{$q}{number} eq "asneeded") {
          $asset{$item}{unlocked}{buy}{asneeded} ||= 1;
        }
        $asset{$item}{unlocked}{buy}{$buyqtty{$q}{id}} ||= 1;
        debuglog(" Unlocked buy-quantity '$q' ($buyqtty{$q}{id}) for $item.");
      }}}
  debuglog(" ba: bought $number, bringing total to $asset{$item}{qtty}.");
  return $number;
}

sub addasset {
  my ($id, $qtty) = @_;
  debuglog("addasset($id, $qtty);");
  $asset{$id}{qtty} += $qtty;
  trackage($id, $qtty, $date);
}

sub trackage {
  my ($assetid, $number, $when) = @_;
  return if not $asset{$assetid}{lifespan};
  my $expires = $when->clone()->add( %{$asset{$assetid}{lifespan}} );
  my ($group) = grep {
    $$_{year} == $expires->year() and $$_{month} == $expires->month()
  } @{$asset{$assetid}{agegroup} || +[]};
  if ($group) {
    $$group{qtty} += $number;
  } else {
    push @{$asset{$assetid}{agegroup}},
      +{ expire => $expires->ymd(), # Actual date of expiration
         year   => $expires->year(),   # Used for fuzzy matching, to
         month  => $expires->month(),  # keep the number of groups low.
         qtty   => $number,
         since  => $when->ymd(),
       };
  }
}

sub expendcash {
  my ($amount, $type, $subcat) = @_;
  $cash -= $amount;
  # TODO: if type is budget, track that it was expended / is no longer set aside
  trackcashflow($amount, $type, $subcat);
}

sub gaincash {
  my ($amount, $type, $subcat) = @_;
  # type will generally be sales for now
  trackcashflow($amount, $type, $subcat);
  $cash += $amount;
  # Percentage-based budget categories, go:
  for my $bk (grep { $budget{$_}{value} =~ /[%]$/ } keys %budget) {
    my ($pct) = $budget{$bk}{value} =~ /(\d+)[%]/;
    my $budgetamt = int($amount * $pct / 100);
    expendcash($budgetamt, "budget", $budget{$bk}{name}) if $budgetamt;
  }
}

sub trackcashflow {
  my ($number, $category, $subcategory) = @_;
  $cashflow{current}{$category}  += $number;
  $cashflow{year}{$category}     += $number;
  $cashflow{total}{$category}    += $number;
  if ($subcategory) {
    $cashflow{sc}{current}{$category}{$subcategory}  += $number;
    $cashflow{sc}{year}{$category}{$subcategory}     += $number;
    $cashflow{sc}{total}{$category}{$subcategory}    += $number;
  }
}

sub updatetopbar {
  my ($w) = @_;
  my $now = DateTime->now( time_zone => $opt{localtimezone} );
  my $dtext = $date->year() . " " . $date->month_abbr() . " " . $date->mday()
    . " " . $date->day_abbr()
    . ($paused ? " PAUSED" : "");
  my $ttext = $now->hour() . ":" . sprintf("%02d", $now->minute());
  my $title = "Eggs v" . $version;
  $$w{text} = join("", map { " " } 0 .. $xmax);
  substr($$w{text}, 1, length($dtext), $dtext);
  substr($$w{text}, $xmax - length($ttext) - 1, length($ttext), $ttext);
  substr($$w{text}, int(($xmax / 2) - (length($title) / 2)), length($title), $title);
}

sub toggle_pause {
  my ($force) = @_;
  if ($paused and not $force) {
    $paused = undef;
    push @message, ["Resumed. ", "meta"];
  } else {
    $paused = 1;
    push @message, ["Paused. ", "meta"];
  }
}

#################################################################################################
#################################################################################################
###
###                                 W I N D O W    I T E M S :
###
#################################################################################################
#################################################################################################

sub windowitems {
  my ($w) = @_;
  my @item;
  # my $wi = ($$w{helpmode} and $$w{helpinfo})
  #  ? $$w{helpinfo}
  #  : $windowitem{$$w{subtype}};
  my $wi = $windowitem{$$w{subtype}};
  if ('CODE' eq ref $wi) {
    @item = $wi->($w);
  } elsif ('ARRAY' eq ref $wi) {
    @item = @{$wi};
  }
  debuglog("windowitems() returning " . @item . " items for " . $$w{title});
  return @item;
}

sub settings_items {
  if ($setting) {
    my ($o) = grep { $$_{name} eq $setting } @option;
    # TODO: maybe support option types
    #       other than enum?
    return @{$$o{enum}};
  } else {
    return ( (map {
      my $o = $_;
      +{ key   => $$o{key},
         name  => $$o{name},
         value => $opt{$$o{name}},
       },
     } grep {
       $$_{key},
     } @option),
             +{ key => "S",
                name => "Save",
                value => "" },
           );
  }
}

sub budget_items {
  if ($budgetitem) {
    # TODO: support things other than enum, maybe at some point
    return map {
      my $e = $_;
      +{ name  => $$e{name},
         key   => $$e{key},
         value => $budget{$budgetitem}{budget}->($$e{name}),
       },
    } @{$budget{$budgetitem}{enum}}
  } else {
    return map {
      +{ key   => $budget{$_}{key},
         name  => $budget{$_}{name},
         value => $budget{$_}{value},
       },
    } sort {
      ($budget{$a}{sort} || $budget{$a}{value}) <=> ($budget{$b}{sort} || $budget{$b}{value})
    } grep {
      (not $budget{$_}{unlock}) or
        ($budget{$_}{unlock} < ($cashflow{total}{sales} || 0))
    } keys %budget;
  }
}

sub init_windowitems {
  return   (
   cashflow => sub {
     my ($w) = @_;
     my $prefix = "";
     debuglog(qq[init_windowitems: cashflow mode is "$$w{mode}".]);
     my @cfitem = (["Sales", "sales", undef],
                   ["Budget", "budget", undef],
                   ["Essentials", "essentials", undef],
                   ["Other Purchases", "purchases", undef],
                   #["Purchases", "purchases", undef]
                  );
     if ($$w{mode}) {
       $prefix = ucfirst($$w{mode}) . " ";
       @cfitem = map {
         [ucfirst($_), $$w{mode}, $_],
       } sort {
         $cashflow{sc}{total}{$$w{mode}}{$a} <=> $cashflow{sc}{total}{$$w{mode}}{$b}
       } keys %{$cashflow{sc}{total}{$$w{mode}}};
     }
     return ( map {
       my ($seclabel, $flowkey) = @$_;
       ( +{ name  => $prefix . $seclabel,
            fg    => "white",
          },
         (map {
           my ($name, $catkey, $subcat) = @$_;
           my @clrinfo = (); @clrinfo = ( fg => "green" ) if $catkey eq "sales";
           my $value = $$w{mode}
             ? ($cashflow{sc}{$flowkey}{$catkey}{$subcat} || 0)
             : ($cashflow{$flowkey}{$catkey} || 0);
           +{ name  => $name,
              value => shownum($value),
              @clrinfo,
            },
         } @cfitem),
         +{ name  => "", },
       )
     } (["This Month", "current"],
        ["Last Month", "lastmonth"],
        ["Last Year",  "lastyear"],
        ["Total",      "total"]));
   },
   buy => sub {
     my $k = "a";
     if ($buyitem) {
       return (+{ name => ucfirst $asset{$buyitem}{name},
                  fg   => "teal",
                },
               map {
                 my $qid = $_;
                 my $q = $buyqtty{$qid};
                 my $price = $$q{price} || $asset{$buyitem}{value} * $$q{pmult};
                 +{ key     => $$q{key},
                    name    => $$q{name},
                    number  => $$q{number},
                    value   => (($$q{number} eq "asneeded")
                                ? ($asset{$buyitem}{asneeded} ? "(on)" : shownum($price))
                                : shownum($price)),
                    cost    => $price,
                    fg      => $$q{fg} || (($price <= $cash) ? "blue" : "grey"),
                    hilight => $$q{hilight} || (($price <= $cash) ? "cyan" : "black"),
                  },
                } grep {
                  $asset{$buyitem}{unlocked}{buy}{$_} or $_ eq "cancel"
                } @{$asset{$buyitem}{buyqtty} || [qw(1 12 144)]}, "cancel"),
                (map {
                  +{ name => $_,
                     fg   => $$wbuy{helpcolor} || $$wbuy{fg},
                   },
                 } format_help_info($wbuy, $asset{$buyitem}{desc}));
     }
     return map {
       my $id = $_;
       +{ id      => $id,
          key     => $k++,
          name    => $asset{$id}{name},
          value   => shownum($asset{$id}{value}),
          fg      => ($asset{$id}{value} <= $cash) ? ($asset{$id}{assetfg} || "green") : "grey",
          hilight => ($asset{$id}{value} <= $cash) ? "yellow" : "black",
        },
     } sort {
       ($asset{$a}{sort} || $asset{$a}{value}) <=> ($asset{$b}{sort} || $asset{$b}{value})
     } grep {
       my $atype = $_;
       $asset{$atype}{good} and
       (grep { $asset{$atype}{unlocked}{buy}{$_} } keys %{$asset{$atype}{unlocked}{buy} || +{}})
     } keys %asset;
   },
   assets   => sub {
     # TODO: specify colors
     return (
             +{ name  => "Cash",
                value => shownum($cash),
                fg    => "gold" },
              (map {
                +{ name  => ucfirst($asset{$_}{plural} || makeplural($asset{$_}{name})),
                   value => shownum($asset{$_}{qtty}),
                   fg    => $asset{$_}{assetfg},
                 },
              } sort {
                $asset{$a}{sort} <=> $asset{$b}{sort}
              } grep {
                $asset{$_}{good} and ($asset{$_}{qtty} >= 1)
              } keys %asset),
            );
   },
   budget   => [budget_items()],
   settings => [settings_items()],
  );
}

#################################################################################################
#################################################################################################
###
###                                          I N P U T:
###
#################################################################################################
#################################################################################################

sub process_key {
  my ($k) = @_;
  debuglog("Processing key '$k' (ordinal value " . ord($k) . ").");
  if ((exists $globalkeybinding{$inputprefix . $k}) and
      (ref $globalkeybinding{$inputprefix . $k}) and
      ('CODE' eq ref $globalkeybinding{$inputprefix . $k})) {
    $globalkeybinding{$inputprefix . $k}->($k);
    $inputprefix = "";
  } elsif ((exists $globalkeybinding{$inputprefix . $k}) and
           ("prefix" eq $globalkeybinding{$inputprefix . $k})) {
    $inputprefix .= $k;
  } elsif ($wfocus and ref $$wfocus{input}) {
    return $$wfocus{input}->($wfocus, $inputprefix . $k);
    $inputprefix = "";
  } else {
    debuglog("Nothing to do with keystroke '$k'.");
  }
}

sub global_key_bindings {
  return (
          chr(9) => sub { # Tab:
            rotate_focus(1); # TODO: test this; I'm not sure it's working.
          },
          # TODO: shift-tab should go the other way.
          chr(16) => sub { # Ctrl-P:
            toggle_pause();
          },
          chr(18) => sub { # Ctrl-R:
            redraw(@_);
          },
          "?" => sub {
            dohelp($wfocus);
          },
          chr(27) => "prefix", # Esc
          chr(27) . chr(79) => "prefix", # Esc O, prefix for function keys F1 - F4
          chr(27) . chr(79) . chr(80) => sub { # F1 = Help
            dohelp($wfocus);
          },
          chr(27) . chr(79) . chr(81) => sub {
            # F2 = [reserved for future use]
          },
          chr(27) . chr(79) . chr(82) => sub { # F3 = Buy
            setfocus($wbuy);
          },
          chr(27) . chr(79) . chr(83) => sub { # F4 = Save
            savegame();
          },
          chr(27) . chr(91) => "prefix", # Esc [
          chr(27) . chr(91) . chr(49) => "prefix", # Esc [1
          chr(27) . chr(91) . chr(49) . chr(53) => "prefix", # Esc [15
          chr(27) . chr(91) . chr(49) . chr(53) . chr(126) => sub { # F5 = Redraw
            redraw(@_);
          },
          chr(27) . chr(91) . chr(49) . chr(55) => "prefix", # Esc [17
          chr(27) . chr(91) . chr(49) . chr(55) . chr(126) => sub { # F6 = Budget
            setfocus($wbudget);
          },
          chr(27) . chr(91) . chr(49) . chr(56) => "prefix", # Esc [18
          chr(27) . chr(91) . chr(49) . chr(56) . chr(126) => sub { # F7 Assets
            setfocus($wassets);
          },
          chr(27) . chr(91) . chr(49) . chr(57) => "prefix", # Esc [19
          chr(27) . chr(91) . chr(49) . chr(57) . chr(126) => sub { # F8 = Messages
            setfocus($wmessages);
          },
          chr(27) . chr(91) . chr(50) => "prefix", # Esc [2
          chr(27) . chr(91) . chr(50) . chr(48) => "prefix", # Esc [20
          chr(27) . chr(91) . chr(50) . chr(48) . chr(126) => sub { # F9 = Cash Flow
            setfocus($wcashflow);
          },
          chr(27) . chr(91) . chr(50) . chr(49) => "prefix", # Esc [21
          chr(27) . chr(91) . chr(50) . chr(49) . chr(126) => sub { # F10 = Settings
            setfocus($wsettings);
          },
          # F11 is intercepted by Konsole, probably other terminals as well, for full-screen.
          chr(27) . chr(91) . chr(50) . chr(52) => "prefix", # Esc [24
          chr(27) . chr(91) . chr(50) . chr(52) . chr(126) => sub { # F12 = Debug
            setfocus($wordkey) if $wordkey;
          },

         );
}

sub dohelp {
  my ($w) = @_;
  my @m;
  if (ref $$w{helpinfo}) {
    if ("ARRAY" eq ref $$w{helpinfo}) {
      @m = @{$$w{helpinfo}};
    } elsif ("CODE" eq ref $$w{helpinfo}) {
      @m = $$w{helpinfo}->();
    } else {
      @m = ("Error: malformed help info for $$w{title}");
    }
  }
  else {
    @m = globalhelp();
    push @m, qq[No widget-specific help info for $$w{title}, sorry.];
  }
  for my $msg (@m) {
    push @message, [$msg, "help"];
  }
}

sub globalhelp {
  return (qq[Press F1 for help, F4 to save, F5 to redraw the screen.  Other function keys select the various widgets, as labeled.]);
}

sub input_cashflow {
  my ($w, $k) = @_;
  $$w{helpmode} = undef;
  if ($k eq "s") {
    $$w{mode} = "sales";
  } elsif ($k eq "b") {
    $$w{mode} = "budget";
  } elsif ($k eq "p") {
    $$w{mode} = "purchases";
  } elsif ($k eq "e") {
    $$w{mode} = "essentials";
  } else {
    $$w{mode} = "";
  }
  debuglog("Set cashflow widget mode to $$w{mode}.");
}
sub input_budget {
  my ($w, $k) = @_;
  if ($budgetitem) {
    my ($e) = grep {
      $$_{key} eq $k
    } @{$budget{$budgetitem}{enum}};
    $budget{$budgetitem}{value} = $$e{name};
    $budgetitem = undef;
  } else {
    ($budgetitem) = grep {
      $budget{$_}{key} eq $k
    } keys %budget;
  }
  $windowitem{budget} = [budget_items()];
}


sub input_buy {
  my ($w, $k) = @_;
  my @item = windowitems($w);
  if ($buyitem) {
    my ($i) = grep { $k eq $$_{key} } @item;
    if (($$i{number} > 0) and ($$i{value} <= $cash)) {
      if (safetobuy($buyitem, $$i{number})) {
        buyasset($buyitem, $$i{number}, $$i{cost}, "player");
      } else {
        if ($asset{$buyitem}{chicken}) {
          $asset{$asset{$buyitem}{housein}}{unlocked}{buy}{1} ||= 1;
        } elsif ($asset{$buyitem}{landsize}) {
          $asset{acre}{unlocked}{1} ||= 1;
        }
        push @message, ["You don't have room for $$i{number} more " .
                        sgorpl($$i{number}, $asset{$buyitem}{name},
                               $asset{$buyitem}{plural}) . ".", "actioncancel"];
      }
    } elsif ($$i{number} eq "cancel") { # Cancel buy-as-needed
      $asset{$buyitem}{asneeded} = undef;
    } elsif ($$i{number} eq "asneeded") { # Start buy-as-needed
      if ($asset{$buyitem}{unlocked}{buy}{asneeded}) {
        $asset{$buyitem}{asneeded} = 1;
      } else {
        debuglog("As-needed not unlocked for $buyitem.");
        push @message, ["Error: buy as needed activated when not unlocked.", "bug"];
      }
    }
    $buyitem = undef;
  } else {
    my ($i) = grep { $k eq $$_{key} } @item;
    # TODO: if the only unlocked buy quantity is 1, go ahead and buy 1 if we can afford it.
    $buyitem = $i ? $$i{id} : undef;
    $debughint = $buyitem;
  }
}

sub input_settings {
  my ($w, $k) = @_;
  my @item = windowitems($w);
  if ($k eq "S") { # This is the hardcoded key for saving the options.
    saveoptions();
  } elsif ($setting) {
    my ($o) = grep { $$_{name} eq $setting } @option;
    # TODO: maybe suport option types other than enum/multiple-choice ?
    my ($i) = grep { $$_{key} eq $k } @item;
    if ($i) {
      $opt{$$o{name}} = $$i{value};
      changed_color_depth() if $setting eq "colordepth";
      $setting = undef;
      $windowitem{settings} = [settings_items()];
    }
  } else {
    my ($i) = grep { $k eq $$_{key} } @item;
    if ($i) {
      $setting = $$i{name};
      $windowitem{settings} = [settings_items()];
    }
  }
}

sub input_ordkey {
  my ($w, $k) = @_;
  my $n = 1;
  while ($$w{"line" . $n}) { $n++; }
  $$w{"line" . $n} = ord $k;
  # If we hit the bottom of the available space, scroll:
  while ($n + 2 > ($$w{ymax} - $$w{y})) {
    for my $p (1 .. $n) {
      $$w{"line" . $p} = $$w{"line" . ($p + 1)} || undef;
    }
    $n--;
  }
  drawscreen($screen);
}

sub setfocus {
  my ($widget) = @_;
  $$wfocus{bg} = undef;
  $wfocus = $widget;
  $$wfocus{bg} = $opt{focusbgcolor};
}

sub rotate_focus { # The user is tabbing from pane to pane.
  my $fid = (ref $wfocus) ? $$wfocus{id} : 0;
  $fid++;
  if ($fid > $wcount) { $fid = 0; }
  while (not grep { $$_{id} eq $fid } @widget) {
    $fid++;
    if ($fid > $wcount) { $fid = 0; }
  }
  setfocus(grep { $$_{id} eq $fid } @widget);
  if ($$wfocus{skipfocus}) {
    # Do not, I repeat, do NOT make all widgets skipfocus.
    rotate_focus();
  }
}

#################################################################################################
#################################################################################################
###
###                                        W I D G E T S :
###
#################################################################################################
#################################################################################################

sub doeggwidget {
  my ($w, $s, @more) = @_;
  my %moropt = @more;
  my $hbg = $opt{focusbgcolor} || $$w{focusbg} || "black";
  my $bg  = (($$w{id} eq $$wfocus{id}) ? $hbg : undef) ||
    ($$w{transparent} ? '__TRANSPARENT__' : $$w{bg}) ||
    '__TRANSPARENT__';
  debuglog("Drawing widget $$w{id} ($$w{type}/$$w{subtype}, $$w{fg}/$$w{focusbg}, $$w{transparent}) on a $bg background.");
  #if ($$w{redraw} or $bg) {
    blankrect($s, $$w{x}, $$w{y}, $$w{xmax} - 1, $$w{ymax} - 1, ($bg eq "__TRANSPARENT__" ? $bg : clr($bg, "bg")));
    doborder($w, $s);
  #}
  my $n = 0;
  for my $i (windowitems($w)) {
    $n++;
    if ($$w{y} + $n + 1 < $$w{ymax}) { # TODO: allow scrolling if needed.
      if ($$i{key}) {
        dotext(+{ id          => $$w{id} . "_keylabel_" . $n,
                  text        => $$i{key},
                  x           => $$w{x} + 1,
                  y           => $$w{y} + $n,
                  bg          => $$w{bg},
                  fg          => $$i{hilight} || $$i{fg} || $$w{hilight} || $$w{fg},
                  transparent => $$w{transparent},
                }, $s);
      }
      dotext(+{ id          => $$w{id} . "_label_" . $n,
                text        => substr($$i{name}, 0, $$w{xmax} -$$w{x} - 2),
                x           => $$w{x} + 1 + ($$i{key} ? 2 : 0),
                y           => $$w{y} + $n,
                bg          => $$w{bg},
                fg          => $$i{fg} || $$w{fg},
                transparent => $$w{transparent},
              }, $s);
      # The value, if present, will write overtop, effectively
      # truncating the label if necessary.  We prefix it with a space
      # to ensure they don't run together.
      dotext(+{ id          => $$w{id} . "_value_" . $n,
                text        => " " . substr($$i{value}, 0, $$w{xmax} - $$w{x} - 3),
                x           => $$w{xmax} - length($$i{value}) - 2,
                y           => $$w{y} + $n,
                bg          => $$w{bg},
                fg          => $$i{fg} || $$w{fg},
                transparent => $$w{transparent},
              }, $s)
        if defined $$i{value};
    }}
}

sub dowidget {
  my ($w, $s, @more) = @_;
  if ($$w{type} eq "clock") {
    doclock($w, $s, @more);
  } elsif ($$w{type} eq "label") {
    dotext($w, $s, @more);
  } elsif ($$w{type} eq "tictactoe") {
    dotictactoe($w, $s, @more);
  } elsif ($$w{type} eq "diffuse") {
    dodiffuse($w, $s, @more);
  } elsif ($$w{type} eq "notepad") {
    donotepad($w, $s, @more);
  } elsif ($$w{type} eq "bargraph") {
    dobargraph($w, $s, @more);
  } elsif ($$w{type} eq "logtail") {
    dologtail($w, $s, @more);
  } elsif ($$w{type} eq "egggame") {
    doeggwidget($w, $s, @more);
  } elsif ($$w{type} eq "messagelog") {
    domessagelog($w, $s, @more);
  } elsif ($$w{type} eq "ordkey") {
    doordkey($w, $s, @more);
  } else {
    dotext($w, $s, @more);
  }
}

sub drawwidgets {
  for my $w (@widget) {
    redraw_widget($w, $screen);
  }
}

sub redraw_widget {
  my ($w, $s) = @_;
  dowidget($w, $s, "redrawonly" => 1);
}

sub dologtail {
  #use File::Tail;
  my ($w, $s, %more)  = @_;
  $$w{__LINES__}    ||= +[];
  if (not $more{redrawonly}) {
    $$w{logfile}      ||= $0;
    $$w{logfile}        = $0 if not -e $$w{logfile};
    #$$w{__FILETAIL__} ||= File::Tail->new($$w{logfile});
    $$w{title}        ||= $$w{logfile};
    $$w{contentsizex} ||= $xmax - $$w{x} - 2;
    $$w{contentsizey} ||= $ymax - $$w{y} - 2;
    $$w{__PADDING__}  ||= " " x $$w{contentsizex};
    my $line;
    #while (defined($line=$$w{__FILETAIL__}->read)) {
    #  chomp $line;
    #  push @{$$w{__LINES__}}, $line;
    #}
    #while ($$w{contentsizey} < scalar @{$$w{__LINES__}}) {
    #  shift @{$$w{__LINES__}};
    #}
    open LOGTAIL, "<", $$w{logfile};
    seek LOGTAIL,-1, 2;  #get past last eol
    my $count=0; my $byte;
    while (1) {
      seek LOGTAIL, -1,1;
      read LOGTAIL, $byte, 1;
      if (ord($byte) == 10) {
        $count++;
        last if $count == $$w{contentsizey};
      }
      seek LOGTAIL,-1,1;
      last if (tell LOGTAIL == 0);
    }
    local $/ = undef;
    my $tail = <LOGTAIL>; close LOGTAIL;
    $$w{__LINES__} = +[ map { chomp $_; $_ } split /\r?\n/, $tail ];
  }
  if (not $$w{__DIDBORDER__}) {
    doborder($w, $s);
    $$w{__DIDBORDER__} = 1 unless $$w{redraw};
  }
  for my $n (1 .. $$w{contentsizey}) {
    my $line = $$w{__LINES__}[$n - 1] || "";
    dotext(+{ id          => $$w{id} . "_line" . $n,
              text        => substr(($line . $$w{__PADDING__}), 0, $$w{contentsizex}),
              x           => $$w{x} + 1,
              y           => $$w{y} + $n,
              transparent => $$w{transparent},
              bg          => $$w{bg},
              fg          => $$w{fg},
            }, $s);
  }
}

sub dobargraph {
  my ($w, $s, %more) = @_;
  if (not $more{redrawonly}) {
    $$w{iter}         ||= 0;
    $$w{bars}         ||= 1 + ($$w{x} + 22 < $xmax) ? 20 : ($xmax - $$w{x} - 2);
    $$w{bars}           = 1 if $$w{bars} < 1;
    $$w{contentsizex} ||= $$w{bars};
    $$w{contentsizey} ||= 5;
    $$w{threshhold}   ||= [5, 15, 25, 35];
    $$w{palette}      ||= "green"; # See %grad in createbggradient
    $$w{gradient}     ||= createbggradient($w);
    $$w{data} ||= +[ map { bgdatum($w, 0) } 1 .. $$w{bars}];
    $$w{minval}       ||= 0;
    $$w{maxval}       ||= $$w{contentsizey} * 8;
    $$w{avgval}       ||= $$w{minval} + (($$w{maxval} - $$w{minval}) / 3);
    push @{$$w{data}}, getnextbgdatum($w);
    shift @{$$w{data}};
    debuglog(Dumper($w));
  }
  if (not $$w{__DIDBORDER__}) {
    doborder($w, $s);
    $$w{__DIDBORDER__} = 1 unless $$w{redraw};
  }
  for my $n (1 .. $$w{contentsizey}) {
    for my $b (0 .. ($$w{bars} - 1)) {
      my $x = $$w{x} + 1 + $b;
      my $y = $$w{y} + $$w{contentsizey} + 1 - $n;
      $$s[$x][$y] = +{ fg   => $$w{data}[$b]{fg} || widgetfg($w),
                       bg   => widgetbg($w, undef, $$s[$x][$y]),
                       char => $$w{data}[$b]{char}[($n - 1)], };
    }
  }
}

sub createbggradient {
  my ($w) = @_;
  $$w{palette} ||= "green";
  $$w{palette} = "green" if $$w{palette} eq "default";
  my %grad = ( green   => +{ start  => +{ h => 151, s =>  37, v =>  80, },
                             finish => +{ h => 100, s => 100, v =>  50, }},
               rainbow => +{ start  => +{ h => 272, s => 100, v => 100, },
                             finish => +{ h =>   0, s =>  93, v => 100, }},
             );
  my $steps = scalar(@{$$w{threshhold}});
  my %delta = map {
    $_ => (($grad{$$w{palette}}{finish}{$_} - $grad{$$w{palette}}{start}{$_}) / $steps),
  } qw(h s v);
  my %current = map { $_ => $grad{$$w{palette}}{start}{$_} } qw(h s v);
  my @c = ();
  for my $s (0 .. $steps) {
    my @min = (($$w{minval} || 0), @{$$w{threshhold}});
    push @c, +{ min => $min[$s],
                h   => $current{h},
                s   => $current{s},
                v   => $current{v},
              };
    $current{$_} += $delta{$_} for qw(h s v);
  }
  @c = map { my $c = hsv2rgb($_);
             #$$c{rgb} = rgb($$c{r}, $$c{g}, $$c{b});
             $c
           } @c;
  #use Data::Dumper; print Dumper(+{ delta    => \%delta,
  #                                  current  => \%current,
  #                                  gradient => \@c,
  #                                  palette  => $$w{palette},
  #                                  gradspec => $grad{$$w{palette}},
  #                                }); <STDIN>;
  return \@c;
}

sub getnextbgdatum {
  my ($w) = @_;
  if ($$w{datasource} eq "load") {
    my ($up, $users, $oneminuteload, $fiveminuteload, $fifteenminuteload) = uptime();
    $$w{corecount} ||= countcpucores($w);
    return bgdatum($w, $oneminuteload # In principle, this number goes from 0 to the number of CPU cores.
                   * $$w{maxval} / (($$w{headroomratio} || 2) * ($$w{corecount} || 1)));
  } else {
    return fakenextbgdatum($w);
  }
}

sub countcpucores {
  my ($w) = @_; # Probably don't actually need this.
  open INFO, "<", "/proc/cpuinfo";
  my $count = 0;
  while (<INFO>) {
    if (/^processor\s*[:]\s*(\d+)/) {
      $count++;
    }
  }
  close INFO;
  return $count;
}

sub fakenextbgdatum {
  my ($w) = @_;
  $$w{hist} ||= +[ map { $$w{avgval} } 1 .. 40 ];
  my $totalhist = 60 * $$w{avgval};# + (5 * $$w{maxval}) + (5 * $$w{minval});
  for my $h (@{$$w{hist}}) { $totalhist += $h }
  my $avg = $totalhist / 100;
  my $num = $avg;
  $$w{flutter} ||= ($$w{maxval} / 20);
  my $flutter = rand($$w{flutter});
  $num = $num - ($$w{flutter} / 2) + $flutter;
  if ($$w{spikeprob} > rand 100) {
    $$w{spike} ||= ($$w{maxval} / 8);
    my $spike = rand($$w{spike});
    $num += rand $spike;
  }
  $num = $$w{minval} if $num < $$w{minval};
  $num = $$w{maxval} if $num > $$w{maxval};
  my $d = bgdatum($w, $num);
  push @{$$w{hist}}, $$d{number};
  shift @{$$w{hist}};
  return $d;
}

sub bgdatum {
  my ($w, $number) = @_;
  $number ||= 0;
  my $fg = ""; # Foreground color irrelevant if printing a space.
  for my $c (@{$$w{gradient}}) {
    $fg = rgb($$c{r}, $$c{g}, $$c{b}) if $$c{min} <= $number;
  }
  my @block = ( +{ min => (1/8), char => "▁" },
                +{ min => (2/8), char => "▂" },
                +{ min => (3/8), char => "▃" },
                +{ min => (4/8), char => "▄" },
                +{ min => (5/8), char => "▅" },
                +{ min => (6/8), char => "▆" },
                +{ min => (7/8), char => "▇" },
                +{ min => (8/8), char => "█" },
              );
  my $valperchar = $$w{maxval} / $$w{contentsizey};
  my @char = map {
    my $n = $_;
    my $c = " ";
    for my $b (@block) {
      if ($number > (($n - 1) * $valperchar) + ($$b{min} * $valperchar)) {
        $c = $$b{char};
      }}
    $c
  } 1 .. $$w{contentsizey};
  ##print rgb(127,127,127,"bg") . $color . "X"; <STDIN>;
  return +{ number => $number,
            iter   => $$w{iter}++,
            fg     => $fg,
            char   => \@char,
          };
}

sub rewrap_message_log {
  my ($w) = @_;
  $$w{msgpos}   = 0;
  $$w{linepos}  = 0;
  $$w{xpos}     = 0;
  $$w{lines}[0] = undef; # The others get cleared when wrapping down
                         # onto them, but the first line can be a work
                         # in progress as far as the wrapping code knows.
  wrap_message_log($w);
}

sub wrap_message_log {
  my ($w) = @_;
  my $msgcount = scalar @{$$w{messages} || +[]};
  my $first = $$w{msgpos};
  for my $msgidx ($first .. ($msgcount - 1)) {
    message_log_wrap_message($w, $msgidx);
    $$w{msgpos}++;
  }
}

sub message_log_wrap_message {
  my ($w, $idx) = @_;
  my ($text, $channel) = @{$$w{messages}[$idx]};
  my $color = $opt{"channelcolor_" . $channel};
  if (not $color) {
    # In some special cases, a color is specified directly (e.g., the
    # color test that is sent when the color depth setting changes).
    my ($cdef) = grep { $$_{name} eq $channel } @clrdef;
    $color = $$cdef{name} if ref $cdef;
    # Last resort, go with the most generic color we've got:
    $color ||= "grey";
  }
  my $width = $$w{xmax} - $$w{x} - 2;
  if (not exists $$w{lines}[$$w{linepos}]) {
    $$w{lines}[$$w{linepos}] = [ map { [" ", ""] } 1 .. $width ];
  }
  for my $word (split /\s+/, $text) {
    if (($width < $$w{xpos} + length($word)) and
        ($width >= length($word))) {
      $$w{linepos}++; $$w{xpos} = 0;
      $$w{lines}[$$w{linepos}] = [ map { [" ", ""] } 1 .. $width ];
    }
    for my $char (split //, $word) {
      $$w{lines}[$$w{linepos}][$$w{xpos}] = [$char, $color];
      $$w{xpos}++;
      if ($$w{xpos} >= $width) { # Unavoidably split long word:
        $$w{linepos}++; $$w{xpos} = 0;
        $$w{lines}[$$w{linepos}] = [ map { [" ", ""] } 1 .. $width ];
      }
    }
    if (($$w{xpos} > 0) and ($$w{xpos} < $width)) {
      $$w{lines}[$$w{linepos}][$$w{xpos}] = [" ", $color];
      $$w{xpos}++;
    }
  }
  if ($$w{onemessageperline}) {
    $$w{linepos}++; $$w{xpos} = 0;
  }
}

sub domessagelog {
  my ($w, $s, %more) = @_;
  if ($$w{redraw}) {
    doborder($w, $s);
  }
  wrap_message_log($w); # Adds any new messages.
  my $width = $$w{xmax} - $$w{x} - 2;
  my $height = $$w{ymax} - $$w{y} - 2;
  my @line = @{$$w{lines}};
  # TODO: scrollpos
  while ($height < scalar @line) {
    shift @line;
  }
  my $y = 0;
  for my $l (@line) {
    $y++;
    for my $x (1 .. $width) {
      $$s[$$w{x} + $x][$$w{y} + $y] = +{ bg   => widgetbg($w, "bg", $$s[$$w{x} + $x][$$w{y} + $y]),
                                         fg   => clr($$l[$x - 1][1]),
                                         char => $$l[$x - 1][0],
                                       },
    }
  }
}

sub format_help_info {
  my ($w, $info) = @_;
  my $width = $$w{xmax} - $$w{x} - 2;
  my @line;
  my ($y, $x) = (0, 0);
  for my $word (split /\s+/, $info) {
    if (not exists $line[$y]) {
      $line[$y] = join("", map { " " } 1 .. $width);
    }
    if (($width < $x + length($word)) and
        ($width >= length($word))) {
      $y++; $x = 0;
      $line[$y] = join("", map { " " } 1 .. $width);
    }
    for my $char (split //, $word) {
      substr($line[$y], $x, 1, $char);
      $x++;
      if ($x >= $width) { # Unavoidably split long words:
        $y++; $x = 0;
        $line[$y] = join("", map { " " } 1 .. $width);
      }
    }
    if (($x > 0) and ($x < $width)) {
      substr($line[$y], $x, 1, " ");
      $x++;
    }
  }
  return @line;
}

sub donotepad {
  my ($w, $s, %more) = @_;
  if ((not $$w{xmax}) or (not $$w{ymax})) {
    $$w{cxmax} = $$w{cymax} = 0;
    for my $k (grep { /^line/ } keys %$w) {
      my ($n) = $k =~ /(\d+)/;
      $$w{cymax} = $n if $$w{cymax} < $n;
      if (not $$w{__DID_UNESCAPES__}) {
        $$w{$k} = notepad_unescape($$w{$k});
      }
      $$w{cxmax} = 1 + length($$w{$k}) if $$w{cxmax} <= length($$w{$k});
    }
    $$w{xmax} = $$w{x} + $$w{cxmax} + 2;
    $$w{ymax} = $$w{y} + $$w{cymax} + 2;
    $$w{__DID_UNESCAPES__} = 1;
  }
  $$w{contentsizex} ||= $$w{xmax} - $$w{x} - 2;
  $$w{contentsizey} ||= $$w{ymax} - $$w{y} - 2;
  doborder($w,$s);
  for my $n (1 .. ($$w{ymax} - $$w{y} - 2)) {
    my $id = $$w{id} . "_line" . $n;
    dotext(+{ id          => $id,
              text        => substr((($$w{"line" . $n} || "") .
                                     (" " x ($$w{xmax} - $$w{x} - 2)), 0, ($$w{xmax} - $$w{x} - 2))),
              x           => $$w{x} + 1,
              y           => $$w{y} + $n,
              bg          => $$w{bg},
              fg          => $$w{fg},
              transparent => $$w{transparent},
            }, $s);
  }
}

sub doordkey {
  # The content gets changed on keyboard input in a different way,
  # but display is the same as a note pad:
  donotepad(@_);
}

sub dodiffuse {
  my ($w, $s, %more) = @_;
  if ($opt{colordepth} < 24) {
    blankrect($s, $$w{x}, $$w{y}, $$w{x} + $$w{contentsizex}, $$w{y} + $$w{contentsizey}, $reset);
  } else {
    if (not $more{redrawonly}) {
      $$w{x}            ||= 0;
      $$w{y}            ||= 0;
      $$w{xmax}         ||= $xmax;
      $$w{ymax}         ||= $ymax;
      $$w{contentsizex} ||= 1 + $$w{xmax} - $$w{x};
      $$w{contentsizey} ||= 1 + $$w{ymax} - $$w{y};
      $$w{title}        ||= "Diffuse";
      $$w{fade}         ||= (0.05 + rand(0.5));
      $$w{paintprob}    ||= 5 + int rand 5;
      $$w{fudge}        ||= 65535 + int rand 65535;
      $$w{offset}         = (defined $$w{offset}) ? $$w{offset} : 2; # Allow edges to behave as middle
      $$w{c} ||= 0;
      $$w{map} ||= +[ map {
        [ map {
          +{ r => 0, g => 0, b => 0 };
        } 0 .. ($$w{ymax} + 2 * $$w{offset}) ]
      } 0 .. ($$w{xmax} + 2 * $$w{offset}) ];
      if ($$w{preseed} and not $$w{__DID_PRESEED__}) {
        $$w{__DID_PRESEED__}++;
        for (1 .. $$w{preseed}) {
          diffuse_addpaint($w);
        }
      }
    }
    diffuse_draw($w, $s);
    if (not $more{redrawonly}) {
      diffuse_diffuse($w);
      diffuse_addpaint($w) if ($$w{paintprob} > rand 100);
    }
  }
}

sub diffuse_draw {
  my ($w, $s) = @_;
  for my $y (0 .. $$w{ymax}) {
    for my $x (0 .. $$w{xmax}) {
      my $mx = $x + $$w{offset};
      my $my = $y + $$w{offset};
      $$s[$$w{x} + $x][$$w{y} + $y]
        = +{ bg => rgb(diffuse_scale($$w{map}[$mx][$my]{r}),
                       diffuse_scale($$w{map}[$mx][$my]{g}),
                       diffuse_scale($$w{map}[$mx][$my]{b}), "bg"),
             fg   => "", # irrelevant
             char => " ", };
    }}
}

sub diffuse_diffuse {
  my ($w) = @_;
  my @old = map {
    [ map { my $x = $_;
            +{ r => $$x{r}, g => $$x{g}, b => $$x{b}, };
          } @$_ ]
  } @{$$w{map}};
  for my $x (2 .. ($$w{xmax} + (2 * $$w{offset}) - 2)) {
    for my $y (1 .. ($$w{ymax} + (2 * $$w{offset}) - 1)) {
      for my $color (qw(r g b)) {
        $$w{map}[$x][$y]{$color} = abs(((1 * $old[$x - 2][$y - 1]{$color}) +
                                        (2 * $old[$x - 2][$y]{$color})     +
                                        (1 * $old[$x - 2][$y + 1]{$color}) +
                                        (2 * $old[$x - 1][$y - 1]{$color}) +
                                        (3 * $old[$x - 1][$y]{$color})     +
                                        (2 * $old[$x - 1][$y + 1]{$color}) +
                                        (3 * $old[$x][$y - 1]{$color})     +
                                        (5 * $old[$x][$y]{$color})         +
                                        (3 * $old[$x][$y + 1]{$color})     +
                                        (2 * $old[$x + 1][$y - 1]{$color}) +
                                        (3 * $old[$x + 1][$y]{$color})     +
                                        (2 * $old[$x + 1][$y + 1]{$color}) +
                                        (1 * $old[$x + 2][$y - 1]{$color}) +
                                        (2 * $old[$x + 2][$y]{$color})     +
                                        (1 * $old[$x + 2][$y + 1]{$color}))
                                       / (33 + $$w{fade}));
        # Fix floating-point underflow:
        $$w{map}[$x][$y]{$color} = int($$w{map}[$x][$y]{$color} * $$w{fudge}) / $$w{fudge};
      }}}
}

sub diffuse_addpaint {
  my ($w) = @_;
  my $c = +{ map { ( $_ => rand 5000 ) } qw(r g b) };
  my $x = $$w{offset} + 1 + int rand($$w{xmax} - 2);
  my $y = $$w{offset} + 1 + int rand($$w{ymax} - 2);
  for (1 .. 1 + int rand 3) {
    for my $z (qw(r g b)) {
      $$w{map}[$x][$y]{$z} += $$c{$z};
    }
    $x += (($x > ($$w{xmax} / 2)) ? -1 : 1) * (1 + int rand ($$w{xsplatter} || $$w{splatter} || 5));
    $y += (($y > ($$w{ymax} / 2)) ? -1 : 1) * (1 + int rand ($$w{ysplatter} || $$w{splatter} || 3));
  }
}

sub dotictactoe {
  my ($w, $s, %more) = @_;
  $$w{title}        ||= "Tic-Tac-Toe";
  $$w{cols}         ||= 3;
  $$w{rows}         ||= 3;
  $$w{squaresizex}  ||= 5;
  $$w{squaresizey}  ||= 3;
  $$w{paddingx}     ||= 2;
  $$w{paddingy}     ||= 1;
  $$w{contentsizex} ||= ($$w{squaresizex} * $$w{cols}) + ($$w{cols} - 1) + (2 * $$w{paddingx});
  $$w{contentsizey} ||= ($$w{squaresizey} * $$w{rows}) + ($$w{rows} - 1) + (2 * $$w{paddingy});
  $$w{board}        ||= [ map { [map { " " } 1 .. $$w{rows}] } 1 .. $$w{cols}];
  $$w{turn}         ||= "X";
  $$w{iter}         ||= 0; $$w{iter}++;
  if (not $$w{__DIDBOARD__}) {
    $$w{title} = $$w{iter} . ($more{redrawonly} ? "R" : "") . ":" . $$w{__INTERVAL_POS__} . "/" . $$w{interval}
      if $$w{debugiter};
    doborder($w,$s);
    blankrect($s, $$w{x} + 1, $$w{y} + 1, $$w{x} + $$w{contentsizex}, $$w{y} + $$w{contentsizey},
              $$w{transparent} ? '__TRANSPARENT__' : widgetbg($w, "boardbg"));
    # We're kind of abusing blankrect() to paint foreground here:
    blankrect($s, $$w{x} + $$w{paddingx} + 1, $$w{y} + $$w{paddingy} + 1,
              $$w{x} + $$w{paddingx} + ($$w{squaresizex} * $$w{cols}) + 2,
              $$w{y} + $$w{paddingy} + ($$w{squaresizey} * $$w{rows}) + 2,
              "", ($$w{boardchar} || "█"), widgetfg($w, "boardfg", "boardbg"));
    tictactoe_clearboard($w,$s);
    $$w{__DIDBOARD__} = 1 unless $$w{redraw};
  }
  tictactoe_taketurn($w) unless $more{redrawonly};
  for my $col (1 .. $$w{cols}) {
    for my $row (1 .. $$w{rows}) {
      my $tilex  = $$w{x} + $$w{paddingx} + (($col - 1) * ($$w{squaresizex} + 1)) + 1;
      my $tiley  = $$w{y} + $$w{paddingy} + (($row - 1) * ($$w{squaresizey} + 1)) + 1;
      my $symbol = $$w{board}[$col - 1][$row - 1];
      $$s[$tilex + int($$w{squaresizex} / 2)][$tiley + int($$w{squaresizey} / 2)] =
        +{ fg    => widgetfg($w, (lc($symbol) || "blankspace") . "fg"),
           bg    => widgetbg($w, (lc($symbol) || "blankspace") . "bg"),
           char  => $symbol, };
    }
  }
}

sub tictactoe_countrow {
  my ($w, $y) = @_;
  my $counts = +{ X => 0, Y => 0, " " => 0 };
  for my $x (0 .. ($$w{cols} - 1)) {
    $$counts{$$w{board}[$x][$y]}++;
  }
  return $counts;
}

sub tictactoe_countcol {
  my ($w, $x) = @_;
  my $counts = +{ X => 0, Y => 0, " " => 0 };
  for my $y (0 .. ($$w{rows} - 1)) {
    $$counts{$$w{board}[$x][$y]}++;
  }
  return $counts;
}

sub tictactoe_countdiagonal {
  my ($w, $dir) = @_;
  my $counts = +{ X => 0, Y => 0, " " => 0 };
  for my $x (0 .. ($$w{cols} - 1)) {
    my $y = ($dir > 0) ? $x : ($$w{cols} - $x - 1);
    $$counts{$$w{board}[$x][$y]}++;
  }
  return $counts;
}

sub tictactoe_taketurn {
  my ($w) = @_;
  if ($$w{turn} > 0) {
    $$w{turn}--;
    if ($$w{turn} == 0) {
      $$w{board} = [ map { [map { " " } 1 .. $$w{rows}] } 1 .. $$w{cols}];
    }
    return;
  }
  my $opponent = ($$w{turn} eq "X") ? "O" : "X";
  my @score = sort { $$b[0] <=> $$a[0] } sort { $$a[3] <=> $$b[3] } map {
    my $x = $_;
    map {
      my $y = $_;
      my $colcount = tictactoe_countcol($w, $x);
      my $rowcount = tictactoe_countrow($w, $y);
      my ($diacounta, $diacountb) = +{ map { $_ => 0 } ("X", "O", " ") };
      if ($$w{rows} == $$w{cols}) {
        if ($x == $y) {
          $diacounta = tictactoe_countdiagonal($w, 1); }
        if ($x + $y == 0) {
          $diacountb = tictactoe_countdiagonal($w, -1); }
      }
      my $score = 500 * $$rowcount{$$w{turn}} + 500 * $$colcount{$$w{turn}}
        + 500 * $$diacounta{$$w{turn}}        + 500 * $$diacountb{$$w{turn}}
        + 300 * $$rowcount{$opponent}         + 300 * $$colcount{$opponent}
        + 300 * $$diacounta{$opponent}        + 300 * $$diacountb{$opponent}
        +  25 * $$diacounta{" "}              + 25 * $$diacountb{" "} # prefer diagonals generally
        + 1;
      if (($$w{board}[$x][$y] eq "X") or ($$w{board}[$x][$y] eq "O")) {
        $score = -1;
      }
      [$score, $x, $y, rand 1000];
    } 0 .. ($$w{rows} - 1)
  } 0 .. ($$w{cols} - 1);
  $$w{board}[$score[0][1]][$score[0][2]] = $$w{turn};
  $$w{turn} = $opponent;
  if (tictactoe_complete($w, $score[0][1], $score[0][2])) {
    $$w{turn} = $$w{windelay} || 5;
  }
}

sub tictactoe_complete {
  # Check whether the move that was just made completed the game.
  # Does not loop over all positions, because that's unnecessary.
  my ($w, $x, $y) = @_;
  my $colcount  = tictactoe_countcol($w, $x);
  my $rowcount  = tictactoe_countrow($w, $y);
  my $diacounta = tictactoe_countdiagonal($w,1);
  my $diacountb = tictactoe_countdiagonal($w,-1);
  return
    (($$colcount{X} == $$w{cols}) or ($$colcount{O} == $$w{cols}) or
     ($$rowcount{X} == $$w{rows}) or ($$rowcount{O} == $$w{rows}) or
     (($$w{cols} == $$w{rows}) and
      (($$diacounta{X} == $$w{cols}) or ($$diacounta{O} == $$w{cols}) or
       ($$diacountb{X} == $$w{cols}) or ($$diacountb{O} == $$w{cols}))));
}

sub tictactoe_clearboard {
  my ($w, $s) = @_;
  for my $col (1 .. $$w{cols}) {
    for my $row (1 .. $$w{rows}) {
      my $tilex = $$w{x} + $$w{paddingx} + (($col - 1) * ($$w{squaresizex} + 1)) + 1;
      my $tiley = $$w{y} + $$w{paddingy} + (($row - 1) * ($$w{squaresizey} + 1)) + 1;
      blankrect($s, $tilex, $tiley, $tilex + $$w{squaresizex} - 1, $tiley + $$w{squaresizey} - 1,
                widgetbg($w, "tilebg"), ($$w{tilechar} || " "), widgetfg($w, "tilefg"));
    }}
}

sub doclock {
  my ($w, $s) = @_;
  my %tzalias = ( localtime => $opt{localtimezone} );
  my $dt = $$w{faketime}
    || DateTime->now(
                     time_zone => ($tzalias{lc $$w{tz}} || $$w{tz}
                                   || $tzalias{localtime}),
                    );
  my $hour = ($dt->hour() % 12); $hour = 12 if $hour < 1;
  $hour = sprintf("%02d",$dt->hour()) if $$w{military};
  my @tpart = ( +[hour => $hour, "fg", "bg"] );
  if (($dt->hour() == 12) and ($dt->minute() < 1)) {
    @tpart = ( +[hour => "Noon", "fg", "bg"] );
  } elsif (($dt->hour() == 0) and ($dt->minute() < 1)) {
    my @tpart = ( +[hour => "Midnight", "fg", "bg"] );
  } else {
    push @tpart, [colona => ":", "colonfg", "colonbg"];
    push @tpart, [minute => sprintf("%02d", $dt->minute()) => "minutefg", "minutebg" ];
    if ($$w{showseconds}) {
      push @tpart, [colonb => ":", "colonfg", "colonbg"];
      push @tpart, [second => sprintf("%02d", $dt->second()), "secondfg", "secondbg" ];
    }
    push @tpart, [pm => "pm", "pmfg", "pmbg" ]
      if (($dt->hour >= 12) and (not $$w{military}));
    push @tpart, [am => "am", "pmfg", "pmbg" ]
      if (($dt->hour < 12) and $$w{showam});
    # Having the sense not to set showam and military for the
    # same clock widget is left as an exercise for the configurer.
  }
  my $time = join "", map { $$_[1] } @tpart;
  my $clen = length($time);
  if (not ($$w{minutefg} || $$w{secondfg} || $$w{colonfg})) {
    @tpart = ( +[ time => $time => "fg" => "bg" ]);
  }
  my $date = $dt->year() . "-" . $dt->month_abbr() . "-" . $dt->mday();
  if ($$w{showdate} and (length($date) > $clen))    { $clen = length($date); }
  if ($$w{title} and (length($$w{title}) > $clen))  { $clen = length($$w{title}); }
  if ($$w{showdow} and length($dt->day_name()) > $clen) { $clen = length($dt->day_name()); }
  if ($$w{contentsizex} and $$w{contentsizey}) {
    # Blank at the _previous_ size (in case it is shrinking):
    blankrect($s, $$w{x}, $$w{y}, $$w{x} + $$w{contentsizex} + 1, $$w{y} + $$w{contentsizey} + 1,
              widgetbg($w), " "); #"░", widgetfg($w));
  }
  $$w{contentsizey} = 1 + ($$w{showdate} ? 1 : 0) + ($$w{showdow} ? 1 : 0);
  $$w{contentsizex} = $clen;
  blankrect($s, $$w{x}, $$w{y}, $$w{x} + $$w{contentsizex} + 1, $$w{y} + $$w{contentsizey} + 1,
            widgetbg($w), " ");
  doborder($w,$s);
  my $pos = $$w{x} + 1 + (($clen > length($time))
                          ? (int(($clen - length($time)) / 2)) : 0);
  for my $p (@tpart) {
    dotext(+{ id          => $$w{id} . "_" . $$p[0],
              x           => $pos,
              y           => $$w{y} + 1,
              fg          => $$w{$$p[2]} || $$w{fg},
              bg          => $$w{$$p[3]} || $$w{bg},
              text        => $$p[1],
              transparent => $$w{transparent},
            }, $s);
    $pos += length($$p[1]);
  }
  if ($$w{showdow}) {
    dotext(+{ id          => $$w{id} . "_dow",
              x           => $$w{x} + 1 + (($clen > length($dt->day_name()))
                                           ? (int(($clen - length($dt->day_name())) / 2)) : 0),
              y           => $$w{y} + 2,
              fg          => $$w{dowfg}  || $$w{datefg} || $$w{fg},
              bg          => $$w{dowbg}  || $$w{datebg} || $$w{bg},
              text        => $dt->day_name(),
              transparent => $$w{transparent},
            }, $s);
  }
  if ($$w{showdate}) {
    dotext(+{ id          => $$w{id} . "_date",
              x           => $$w{x} + 1 + (($clen > length($date))
                                           ? (int(($clen - length($date)) / 2)) : 0),
              y           => $$w{y} + 2 + ($$w{showdow} ? 1 : 0),
              fg          => $$w{datefg} || $$w{fg},
              bg          => $$w{datebg} || $$w{bg},
              text        => $date,
              transparent => $$w{transparent},
            }, $s);
  }
}

sub blankrect {
  my ($s, $minx, $miny, $maxx, $maxy, $bg, $c, $fg) = @_;
  for my $x ($minx .. $maxx) {
    for my $y ($miny .. $maxy) {
      $$s[$x][$y] = +{ bg   => ($bg eq '__TRANSPARENT__') ? $$s[$x][$y]{bg} : $bg,
                       fg   => ($fg || ""),
                       char => ((defined $c) ? $c : " "),
                     };
    }}}

sub doborder {
  my ($w, $s) = @_;
  my $fg = widgetfg($w, "borderfg");
  $$s[$$w{x}][$$w{y}] = +{ char => "╔", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x}][$$w{y}]) };
  $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y}] = +{ char => "╗", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y}]) };
  $$s[$$w{x}][$$w{y} + $$w{contentsizey} + 1] = +{ char => "╚", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x}][$$w{y} + $$w{contentsizey} + 1]) };
  $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y} + $$w{contentsizey} + 1]
    = +{ char => "╝", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y} + $$w{contentsizey} + 1]) };
  for my $x (1 .. $$w{contentsizex}) {
    $$s[$$w{x} + $x][$$w{y}] = +{ char => "═", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x} + $x][$$w{y}]) };
    $$s[$$w{x} + $x][$$w{y} + $$w{contentsizey} + 1] = +{ char => "═", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x} + $x][$$w{y} + $$w{contentsizey} + 1]) };
  }
  for my $y (1 .. $$w{contentsizey}) {
    $$s[$$w{x}][$$w{y} + $y] = +{ char => "║", fg => $fg, bg => widgetbg($w, "borderbg", $$s[$$w{x}][$$w{y} + $y]) };
    $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y} + $y] = +{ char => "║", fg => $fg, bg => $reset . widgetbg($w, "borderbg", $$s[$$w{x} + $$w{contentsizex} + 1][$$w{y} + $y]) };
  }
  if ($$w{title}) {
    dotext(+{ id          => $$w{id} . "_title",
              x           => $$w{x} + 1 + (($$w{contentsizex} > length($$w{title}))
                                           ? (int(($$w{contentsizex} - length($$w{title})) / 2)) : 0),
              y           => $$w{y},
              fg          => ($$w{id} eq $$wfocus{id}) ? "white" : $$w{titlefg} || $$w{borderfg} || $$w{fg},
              bg          => $$w{titlebg} || $$w{borderbg} || $$w{bg},
              text        => $$w{title},
              transparent => $$w{transparent},
            }, $s);
  }
}

sub dotext {
  my ($t, $s) = @_;
  my ($ut, $users) = uptime();
  my %magictext = ( __UPTIME__ => $ut,
                    __USERS__  => $users . " users", );
  if (not $$t{__DONE__}) {
    my $text = (defined $$t{text}) ? $$t{text} : $$t{title} || $$t{type} || "t_$$t{id}";
    $text = $magictext{$text} || $text;
    $$t{rows} = 1;
    $$t{cols} = length $text;
    my $x = ($$t{x} >= 0) ? $$t{x} : ($xmax + $$t{x} - $$t{cols});
    for my $c (split //, $text) {
      $$s[$x][$$t{y}] = +{ bg   => widgetbg($t, "bg", $$s[$x][$$t{y}]),
                           fg   => widgetfg($t),
                           char => $c };
      $x++;
    }
  }
}

sub widgetfg {
  my ($w, $fgfield) = @_;
  return "" if $opt{colordepth} < 4;
  $fgfield ||= "fg"; $fgfield = "fg" if not $$w{$fgfield};
  return #(ref $$w{$fgfield}) ? rgb(@{$$w{$fgfield}}) :
    clr($$w{$fgfield}) || "";
}

sub widgetbg {
  my ($w, $bgfield, $old) = @_;
  return "" if $opt{colordepth} < 4;
  $bgfield ||= ($$w{id} eq $$wfocus{id}) ? "focusbg" : "bg";
  $bgfield = "bg" if not $$w{$bgfield};
  if ($$w{transparent} and $$w{id} ne $$wfocus{id}) {
    return $$old{bg} if $$old{bg};
  }
  return #(ref $$w{$bgfield}) ? rgb(@{$$w{$bgfield}},"bg") :
    clr($$w{$bgfield} || "black", "bg") || "";
}

#################################################################################################
#################################################################################################
###
###                                     S A V E  /  L O A D :
###
#################################################################################################
#################################################################################################

sub get_config_dir {
  my $homedir = $ENV{HOME} || File::HomeDir->my_home || cwd();
  # TODO: check for MS Windows and do AppData things here.
  my $path = catfile($homedir, ".config", "Eggs");
  return $path if -d $path;
  system("mkdir", "-p", $path);
  die "Path does not exist: $path" if not -e $path;
  die "Not a directory: $path" if not -d $path;
  return $path;
}

sub loadoptions {
  my ($o) = @_;
  my $fn = $$o{optionsfile} || catfile(get_config_dir(), "eggs.cfg");
  if (-e $fn) {
    open OPT, "<", $$o{optionsfile} or die "Cannot read options file $$o{optionsfile}: $!";
    debuglog("Reading options file ($$o{optionsfile}).");
    while (<OPT>) {
      my $line = $_;
      if ($line =~ /^Eggs v(.*) Options File$/) {
        my ($ver) = $1;
        if ($ver ne $version) {
          debuglog("Options file was written with version $ver, but we are reading it with version $version.");
        }
      } elsif ($line =~ /^\s*$/) {
        # Ignore blank line.
      } elsif ($line =~ /^\s*#/) {
        # Ignore comment line.
      } elsif ($line =~ /^\s*([^=]+)[=](.*?)\s*$/) {
        my ($key, $val) = ($1, $2);
        my ($opt) = grep { $$_{name} eq $key } @option;
        if (ref $opt) {
          if ($$opt{save} =~ /user/) {
            if (ref $$opt{enum}) {
              my ($e) = grep { $$_{value} eq $val } @{$$opt{enum}};
              if (ref $e) {
                $$o{$key} = $$e{value};
              } else {
                debuglog("Options file specified unknown value for option: '$key' = '$val'");
              }
            } elsif (ref $$opt{regex}) {
              my ($washed) = ($val =~ $$opt{regex});
              if ($washed and ($washed eq $val)) {
                $$o{$key} = $washed;
              } else {
                debuglog("Options file specified irregular value for option: '$key' = '$val'")
              }
            } else {
              debuglog("Don't know how to validate value for option: '$key' = '$val'");
            }
          } else {
            debuglog("Options file contains an option it should not: '$key' = '$val'");
          }
        } else {
          debuglog("Options file contains spurious option: '$key' = '$val'");
        }
      }
    }
    close OPT;
    return $o;
  } else {
    debuglog("Options file does not exist: $fn");
    return;
  }
}

sub saveoptions {
  my $fn = $opt{optionsfile} || catfile(get_config_dir(), "eggs.cfg");
  open OPT, ">", $fn or die "Cannot write options file '$fn': $!";
  print OPT "Eggs v" . $version . " Options File\n";
  for my $o (grep { $$_{save} =~ /user/ } @option) {
    print OPT "\n";
    print OPT qq[# $$o{desc}\n];
    print OPT qq[# default: $$o{default}\n];
    print OPT qq[$$o{name}=$$o{value}\n];
  }
  print OPT qq[\n\n## EOF\n\n];
  close OPT;
  push @message, ["Options saved.", "meta"];
}

sub restoregame {
  my ($fn) = @_;
  $fn ||= $opt{savefile} || catfile(get_config_dir(), "eggs.save");
  debuglog("Restoring $fn");
  if (open SAV, "<", $fn) {
    my %restored;
    while (<SAV>) {
      my $line = $_;
      if ($line =~ /^\s*Global[:](Date|RunStarted|NGPETA)=(\d+)-(\d+)-(\d+)/) {
        my ($whichdate, $y, $m, $d) = ($1, $2, $3, $4);
        my $dt = DateTime->new( year  => $y,
                                month => $m,
                                day   => $d,
                                hour  => 6,
                              );
        if ($whichdate eq "Date") {
          $date = $dt;
        } elsif ($whichdate eq "RunStarted") {
          $runstarted = $dt;
        } elsif ($whichdate eq "NGPETA") {
          $ngpeta = $dt;
        } else {
          die "Unknown date variable: '$whichdate'.";
        }
        $restored{global}++;
      } elsif ($line =~ /^\s*Global[:]Cash=(\d+) zorkmid/) {
        $cash = $1;
        $restored{global}++;
      } elsif ($line =~ /^\s*Global[:]Lvl=(.*?)\w*$/) {
        ($breedlvl, $genlvl, $genleak) = split /,/, $1;
        $restored{global}++;
      } elsif ($line =~ /^\s*Mode[:](\w+)=(.*?)\s*$/) {
        my ($wst, $mode) = ($1, $2);
        my ($w) = grep { $$_{subtype} eq $wst } @widget;
        if (ref $w) {
          $$w{mode} = $mode;
        } else {
          debuglog("Widget not found: $wst");
        }
      } elsif ($line =~ /^\s*Asset[:](\w+)=(\d*);([^;]*);([^;]*);(.*)/) {
        my ($atype, $num, $an, $unl, $trk) = ($1, $2, $3, $4, $5);
        $asset{$atype}{qtty} = $num;
        $asset{$atype}{asneeded} = ($an =~ /buy/) ? "buy" : undef;
        $restored{asset}++;
        if ($unl =~ /unlocked.buy=(.*)/) {
          my $list = $1;
          $asset{$atype}{unlocked}{buy} = +{ map { $_ => 1 } split /,\s*/, $list };
        }
        $asset{$atype}{agegroup} = +[
                                     map {
                                       my $t = $_;
                                       my ($q, $y, $m, $e, $s) = split /,\s*/, $t;
                                       $restored{agegroup}++;
                                       +{ qtty => $q, year => $y, month => $m,
                                          expire => $e, since => $s,
                                        };
                                     } grep { $_ } split /;\s*/, $trk
                                    ];
      } elsif ($line =~ /^\s*Budget[:](\w+)[:](.*?)\s*$/) {
        my ($bk, $val) = ($1, $2);
        $budget{$bk}{value} = $val;
        $restored{budget}++;
        #debuglog("Set budget for '$bk' to $budget{$bk}{value}")
      } elsif ($line =~ /^\s*CF[:](\w+)[:]([^:]+)/) {
        my ($timeframe, $rest) = ($1, $2);
        for my $pair (split /,\s*/, $rest) {
          my ($category, $number) = $pair =~ /([^=]+)[=](.*?)\s*$/;
          $cashflow{$timeframe}{$category} = $number;
          $restored{cashflow}++;
        }
      } elsif ($line =~ /^\s*CFSC[:](\w+)[:](\w+)[:](.*?)\s*$/) {
        my ($timeframe, $category, $rest) = ($1, $2, $3);
        for my $pair (split /,\s*/, $rest) {
          my ($subcat, $number) = $pair =~ /^([^=]+)=(.*)/;
          $cashflow{sc}{$timeframe}{$category}{$subcat} = $number;
          $restored{cfsubcat}++;
        }
      } elsif ($line =~ /^\s*Option[:]([^=]+)=(.*?)\s*$/) {
        my ($name, $value) = ($1, $2);
        $opt{$name} = $value if defined $value;
        $restored{option}++;
      } elsif ($line = /^\s*Message[:]([^:]+)[:](.*)/) {
        my ($channel, $text) = ($1, $2);
        push @message, [$text, $channel];
        $restored{message}++;
      } elsif ($line =~ /^#/) {
        # Comment line, ignore it.
      } elsif ($line =~ /^\s*$/) {
        # Nothing but whitespace, ignore it.
      } else {
        die "restoregame(): failed to parse line: $line\n";
      }
    }
    #$windowitem{settings} = [settings_items()] if $restored{option};
    #$windowitem{budget}   = [budget_items()] if $restored{budget};
    %windowitem = init_windowitems();
    push @message, ["Restored.", "meta"];
    close SAV;
    debuglog("Restored ($_): $restored{$_}") for sort { $a cmp $b } keys %restored;
  } else {
    debuglog("Cannot read from save game file '$fn': $!");
  }
}

sub savegame {
  my $fn = $opt{savefile} || catfile(get_config_dir(), "eggs.save");
  open SAV, ">", $fn or die "Cannot write to save game file '$fn': $!";
  print SAV "Eggs v" . $version . " Saved Game\n";
  print SAV qq[#### Globals\n];
  for my $d (["Date", $date],
             ["RunStarted", $runstarted],
             ["NGPETA", $ngpeta],
            ) {
    my ($name, $dt) = @$d;
    print SAV "Global:" . $name . "=" . sprintf("%04d", $dt->year()) . "-" . sprintf("%02d", $dt->month()) . "-" . sprintf("%02d", $dt->mday()) . "\n";
  }
  print SAV qq[Global:Cash=] . $cash . " zorkmids\n";
  print SAV qq[Global:Lvl=] . (join ",", map { 0 + $_ } ($breedlvl, $genlvl, $genleak)) . "\n";
  print SAV qq[#### Assets\n];
  for my $atype (sort { ($asset{$a}{sort} || $asset{$a}{value}) <=> ($asset{$b}{sort} || $asset{$b}{value}) } keys %asset) {
    my $unl = (ref $asset{$atype}{unlocked}{buy})
      ? qq[unlocked.buy=] . join(",", grep { $asset{$atype}{unlocked}{buy}{$_}
                                           } keys %{ $asset{$atype}{unlocked}{buy}})
      : "";
    my $trk = join(";", map {
      my $g = $_;
      join ",", map { $$g{$_} } qw(qtty year month expire since);
    } @{$asset{$atype}{agegroup}});
    my $an  = $asset{$atype}{asneeded} ? "asneeded=buy" : "";
    print SAV qq[Asset:$atype=$asset{$atype}{qtty};$an;$unl;$trk\n];
  }
  print SAV qq[#### Cashflow Section\n];
  print SAV qq[Mode:$$wcashflow{subtype}=$$wcashflow{mode}\n];
  for my $k (qw(current lastmonth year lastyear total)) {
    print SAV qq[CF:$k:] . join(",", map { $_ . "=" . $cashflow{$k}{$_} } keys %{$cashflow{$k}}) . "\n";
    for my $cat (keys %{$cashflow{sc}{$k}}) {
      print SAV qq[CFSC:$k:$cat:] . (join(",", map {
        $_ . "=" . $cashflow{sc}{$k}{$cat}{$_}
      } keys %{$cashflow{sc}{$k}{$cat}})) . "\n";
    }}
  print SAV qq[#### Budget Section\n];
  for my $bk (keys %budget) {
    print SAV qq[Budget:$bk:$budget{$bk}{value}\n];
  }
  print SAV qq[#### Options Section\n];
  for my $o (grep { $$_{save} =~ /game/ } @option) {
    print SAV qq[Option:$$o{name}=$opt{$$o{name}}\n];
  }
  print SAV qq[#### Messages Section\n];
  for my $m (@message) {
    my ($text, $channel) = @$m;
    $text =~ s/\n/ /g; # Messages _shouldn't_ have any newlines anyway.
    print SAV qq[Message:$channel:$text\n];
  }
  print SAV qq[#### EOF\n\n];
  close SAV;
  push @message, ["Saved.", "meta"];
  return;
}

#################################################################################################
#################################################################################################
###
###                                        D I S P L A Y :
###
#################################################################################################
#################################################################################################

sub changed_color_depth {
  redraw();
  color_test();
}

sub redraw {
  rewrap_message_log($wmessages);
  refreshscreen();      # Clear artifacts from $screen, and redo the layout.
  drawwidgets();        # Populate $screen
  drawscreen();         # Actually draw $screen to terminal
}

sub drawscreen {
  my ($s) = @_;
  if ($opt{nohome}) {
    print $reset . "\n\n";
  } else {
    print chr(27) . "[H" . $reset;
  }
  for my $y (0 .. $ymax) {
    if (not ($y == $ymax)) {
      print gotoxy(0, $y);
      print $reset;
    }
    my $lastbg = "";
    my $lastfg = "";
    for my $x (0 .. $xmax) {
      print "" . ((((($$s[$x][$y]{bg} || "") eq $lastbg) and
                    (($$s[$x][$y]{fg} || "") eq $lastfg))
                   ? "" : ((($$s[$x][$y]{bg} || "") . ($$s[$x][$y]{fg} || "")) || "")))
               . (length($$s[$x][$y]{char}) ? ($$s[$x][$y]{char} || " ") : " ")
        unless (($x == $xmax) and
                ($y == $ymax) and
                (not $opt{fullrect}));
      $lastbg = $$s[$x][$y]{bg} || "";
      $lastfg = $$s[$x][$y]{fg} || "";
    }
  }
}

sub refreshscreen {
  layout();
  $screen = +[
              map {
                [ map {
                  +{ char => " ",
                     bg   => clr("black"),
                   };
                } 0 .. $ymax ]
              } 0 .. $xmax ];
}

sub layout {
  ($xmax, $ymax) = Term::Size::chars *STDOUT{IO};
  $xmax ||= 80;
  $ymax ||= 24;
  $xmax--; #$ymax--; # Term::Size::chars returns counts, not zero-indexed maxima.
  #$opt{xmax} ||= $xmax;
  #$opt{ymax} ||= $ymax;
  $xmax = $opt{xmax} if $opt{xmax} and ($xmax > $opt{xmax});
  $ymax = $opt{ymax} if $opt{ymax} and ($ymax > $opt{ymax});
  my $leftsize  = ($xmax > 100) ? int($xmax / 5) : 20;
  my $rightsize = ($xmax > 100) ? int($xmax / 5) : 20;
  my $msgheight = int($ymax / 2); # TODO: maybe adjust this.
  my $budgetheight = 12;
  $wbg = +{ x => 0, y => 1, xmax => $xmax, ymax => $ymax,
            type => "diffuse",
            redraw => 1, };
  #if ($ymax > 26) {
  #  $wrealclock = +{ type => "clock",
  #                   x => 0, y => $ymax - 5,
  #                   fg        => "green",
  #                   title     => "RealTime",
  #                   showdate  => 1,
  #                   showdow   => 1,
  #                   showam    => 1,
  #                   minutefg  => "spring green",
  #                   colonfg   => "blue",
  #                   dowfg     => "green",
  #                   borderfg  => "green",
  #                   redraw    => 1,
  #                   skipfocus => 1,
  #                   id        => $wcount++,
  #                 };
  #  $wgameclock = +{ type      => "clock",
  #                   faketime  => $date,
  #                   skipfocus => 1,
  #                   x => 12, y => $ymax - 5,
  #                   fg        => "cyan",
  #                   title     => "GameTime",
  #                   showdate  => 1,
  #                   showdow   => 1,
  #                   showam    => 1,
  #                   minutefg  => "azure",
  #                   colonfg   => "blue",
  #                   dowfg     => "cyan",
  #                   borderfg  => "teal",
  #                   redraw    => 1,
  #                   id        => $wcount++,
  #                 };
  #} else {
  #  $wrealclock = undef;
  #  $wgameclock = undef;
  #}
  $wtopbar   = +{ type => "text", title => "Eggs Titlebar", redraw => 0,
                  text => join("", map { " " } 0 .. $xmax),
                  x => 0, y => 1, xmax => $xmax, ymax => 1,
                  bg => "brown", fg => "azure",
                  #bg => "black", fg => "indigo",
                  #bg => "white", fg => "black",
                  #transparent => 0,
                };
  $wcashflow = +{ type => "egggame", subtype => "cashflow", title => "Cash Flow (F9)", mode => "",
                  redraw => 1, x => 0, y => 2, xmax => $leftsize - 1,
                  ymax => $ymax,# - ($wgameclock ? 5 : 0),
                  fg => "gold", focusbg => 'brown', id => $wcount++, transparent => 1,
                  input => sub { input_cashflow(@_); },
                  #helpinfo => sub {
                  #  my ($w) = @_;
                  #  return map {
                  #    +{ text => $_, },
                  #  } (format_help_info($w, qq[Press s, b, e, or p to view details about sales, budget expenses, essentials, or purchases, respectively.]),
                  #     format_help_info($w, qq[Press o to return to the overview.]));
                  #},
                  helpinfo => [ qq[Press s, b, e, or p to view details about sales, budget expenses, essentials, or purchases, respectively.],
                                qq[Press o to return to the overview.],
                              ],
                };
  $wmessages = +{ type => "messagelog", subtype => "messages", title => "Messages (F8)", redraw => 1,
                  x => $leftsize, y => 2, xmax => $xmax - $rightsize - 2, ymax => $msgheight + 1,
                  messages => \@message, lines => \@messageline,
                  msgpos => 0, linepos => 0, xpos => 0,
                  fg => "spring green", focusbg => "grey", id => $wcount++,
                  transparent => 1,
                };
  $wassets = +{ type => "egggame", subtype => "assets", title => "Assets (F7)", redraw => 1,
                x => $xmax - $rightsize - 1, xmax => $xmax, fg => "indigo", focusbg => "red",
                y => 2, ymax => $ymax - $budgetheight, id => $wcount++, transparent => 1,
              };
  $wbudget = +{ type => "egggame", subtype => "budget", title => "Budget (F6)", redraw => 1,
                x => $xmax - $rightsize - 1, xmax => $xmax,
                y => $ymax - $budgetheight, ymax => $ymax,
                fg => "purple-red", focusbg => "purple", id => $wcount++, transparent => 1,
                input => sub { input_budget(@_); },
              };
  if ($opt{debug}) {
    $wordkey = +{ type => "ordkey", title => "OrdKey F12", redraw => 1,
                  line1 => "Press Keys",
                  x => $leftsize, y => $msgheight + 1, xmax => $leftsize + 12, ymax => $ymax,
                  input => sub { input_ordkey(@_); },
                  fg => "purple", #bg => "purple",
                  id => $wcount++,
                };
  }
  my $middlesize = $xmax - $leftsize - $rightsize - ($wordkey ? 12 : 0);
  my $buysize = int($middlesize * 3 / 5) - 1;
  $wbuy = +{ type => "egggame", subtype => "buy", title => "Buy (F3)", redraw => 1,
             x => $leftsize + ($wordkey ? 12 : 0), y => $msgheight + 1, ymax => $ymax,
             xmax => $leftsize + ($wordkey ? 12 : 0) + $buysize,
             input => sub { input_buy(@_); },
             fg => "teal", focusbg => "cyan", id => $wcount++,
             transparent => 1,
           };
  $wsettings = +{ type => "egggame", subtype => "settings", title => "Settings (F10)", redraw => 1,
                  x => $leftsize + ($wordkey ? 12 : 0) + $buysize, y => $msgheight + 1, ymax => $ymax,
                  xmax => $xmax - $rightsize - 2,
                  input => sub { input_settings(@_); },
                  fg => "cyan", focusbg => "green", id => $wcount++,
                  transparent => 1,
                };
  $wfocus ||= $wbuy;
  @widget = grep { $_ and not $$_{disabled}
                 } ($wbg, $wtopbar, $wcashflow,
                    #$wgameclock, $wrealclock,
                    $wmessages, $wordkey, $wbuy, $wsettings,
                    $wassets, $wbudget);
  for my $w (@widget) {
    $$w{contentsizex} ||= $$w{xmax} - $$w{x} - 2;
    $$w{contentsizey} ||= $$w{ymax} - $$w{y} - 2;
  }
}

sub hsv2rgb {
  my ($c) = @_;
  use Imager::Color;
  my $hsv = Imager::Color->new( hsv =>  [ $$c{h}, ($$c{v} / 100), ($$c{s} / 100) ] ); # hue, val, sat
  ($$c{r}, $$c{g}, $$c{b}) = $hsv->rgba;
  return $c;
}

sub rgb { # Return terminal code for a 24-bit color.
  my ($red, $green, $blue, $isbg) = @_;
  push @message, ["rgb() called at inappropriate color depth.", "bug"]
    if $opt{colordepth} < 24;
  my $fgbg = ($isbg) ? 48 : 38;
  my $delimiter = ";";
  return "\x1b[$fgbg$ {delimiter}2$ {delimiter}$ {red}"
    . "$ {delimiter}$ {green}$ {delimiter}$ {blue}m";
}

sub bg8 {
  my ($cnum) = @_;
  return eightbitcolorcode($cnum, "bg");
}
sub fg8 {
  my ($cnum) = @_;
  return eightbitcolorcode($cnum);
}
sub eightbitcolorcode {
  my ($cnum, $isbg) = @_;
  my $fgbg = $isbg ? 48 : 38;
  return chr(27) . qq([$fgbg;5;${cnum}m);
}

sub color_test {
  push @message, ["Color Test: ", "meta"];
  for my $fg (@clrdef) {
    push @message, [$$fg{name}, $$fg{name}];
    # TODO: and show that on various backgrounds.
  }
}

sub colordefs {
  # Alphabetical list of keys:
  # c - cyan
  # d - gold
  # e - purple-red
  # g - green
  # h - hot pink
  # i - indigo
  # k - black
  # l - blue
  # m - magenta
  # n - brown
  # o - orange
  # p - pink
  # q - red-orange
  # r - red
  # s - grey (mnemonic: silver)
  # t - teal
  # u - purple
  # v - various (widget-defined)
  # w - white
  # x - spring green
  # y - yellow
  # z - azure
  return (+{ name => "white",
             key    => "w",
             r      => 250,
             g      => 250,
             b      => 250,
             fg8    => fg8(255),
             bg8    => bg8(243),
             ansifg => color("bold white"),
             ansibg => color("on_white"),
           },
          +{ name   => "grey",
             key    => "s",
             r      => 200,
             g      => 200,
             b      => 200,
             fg8    => fg8(251),
             bg8    => bg8(240),
             ansifg => color("white"),
             ansibg => color("on_white"),
           },
          +{ name   => "black",
             key    => "k",
             r      => 128,
             g      => 128,
             b      => 128,
             fg8    => fg8(243),
             bg8    => bg8(232),
             ansifg => color("bold black"),
             ansibg => color("on_black"),
           },
          +{ name => "red",
             key    => "r",
             r      => 200,
             g      => 0,
             b      => 0,
             fg8    => fg8(160),
             bg8    => bg8(88),
             ansifg => color("bold red"),
             ansibg => color("on_red"),
           },
          +{ name   => "red-orange",
             key    => "q",
             r      => 255,
             g      => 100,
             b      => 0,
             fg8    => fg8(202),
             bg8    => bg8(88),
             ansifg => color("bold red"),
             ansibg => color("on_red"),
           },
          +{ name   => "orange",
             key    => "o",
             r      => 255,
             g      => 126,
             b      => 0,
             fg8    => fg8(208),
             bg8    => bg8(130),
             ansifg => color("bold red"),
             ansibg => color("on_red"),
           },
          +{ name   => "gold",
             key    => "d",
             r      => 255,
             g      => 176,
             b      => 0,
             fg8    => fg8(214),
             bg8    => bg8(94),
             ansifg => color("bold yellow"),
             ansibg => color("on_yellow"),
           },
          +{ name   => "yellow",
             key    => "y",
             r      => 255,
             g      => 255,
             b      => 0,
             fg8    => fg8(11),
             bg8    => bg8(94),
             ansifg => color("bold yellow"),
             ansibg => color("on_yellow"),
           },
          +{ name   => "spring green",
             key    => "x",
             r      => 214,
             g      => 255,
             b      => 0,
             fg8    => fg8(190),
             bg8    => bg8(100),
             ansifg => color("bold yellow"),
             ansibg => color("on_yellow"),
           },
          +{ name   => "green",
             key    => "g",
             r      => 0,
             g      => 255,
             b      => 0,
             fg8    => fg8(46),
             bg8    => bg8(22),# or 28?
             ansifg => color("bold green"),
             ansibg => color("on_green"),
           },
          +{ name   => "teal",
             key    => "t",
             r      => 50,
             g      => 240,
             b      => 153,
             fg8    => fg8(158),
             bg8    => bg8(22),# or 29?
             ansifg => color("bold cyan"),
             ansibg => color("on_cyan"),
           },
          +{ name   => "cyan",
             key    => "c",
             r      => 0,
             g      => 255,
             b      => 255,
             fg8    => fg8(44),
             bg8    => bg8(30),
             ansifg => color("bold cyan"),
             ansibg => color("on_cyan"),
           },
          +{ name   => "azure",
             key    => "z",
             r      => 96,
             g      => 210,
             b      => 255,
             fg8    => fg8(45),
             bg8    => bg8(31),
             ansifg => color("bold cyan"),
             ansibg => color("on_blue"),
           },
          +{ name   => "blue",
             key    => "l",
             r      => 100,
             g      => 100,
             b      => 255,
             fg8    => fg8(21),
             bg8    => bg8(18),
             ansifg => color("bold blue"),
             ansibg => color("on_blue"),
           },
          +{ name   => "indigo",
             key    => "i",
             r      => 143,
             g      => 96,
             b      => 255,
             fg8    => fg8(147),
             bg8    => bg8(17), # or 54
             ansifg => color("bold blue"),
             ansibg => color("on_blue"),
           },
          +{ name   => "purple",
             key    => "u",
             r      => 181,
             g      => 0,
             b      => 236,
             fg8    => fg8(177),
             bg8    => bg8(53),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
          +{ name   => "magenta",
             key    => "m",
             r      => 255,
             g      => 0,
             b      => 255,
             fg8    => fg8(201),
             bg8    => bg8(53),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
          +{ name   => "hot pink",
             key    => "h",
             r      => 255,
             g      => 0,
             b      => 236,
             fg8    => fg8(199),
             bg8    => bg8(89),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
          +{ name   => "pink",
             key    => "p",
             r      => 255,
             g      => 157,
             b      => 245,
             fg8    => fg8(218),
             bg8    => bg8(138),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
          +{ name   => "purple-red",
             key    => "e",
             r      => 240,
             g      => 102,
             b      => 170,
             fg8    => fg8(162),
             bg8    => bg8(52),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
          +{ name   => "brown",
             key    => "n",
             r      => 219,
             g      => 161,
             b      => 57,
             fg8    => fg8(178),
             bg8    => bg8(95),
             ansifg => color("bold magenta"),
             ansibg => color("on_magenta"),
           },
        );
}

sub clr {
  my ($cname, $bg) = @_;
  return "" if $opt{colordepth} < 4;
  return "" if not $cname;
  my ($cdef) = grep { $$_{name} eq $cname } @clrdef;
  die "No such color: $cname" if not ref $cdef;
  if ($opt{colordepth} >= 24) {
    if ($bg) {
      return rgb(int($$cdef{r} / 3), int($$cdef{g} / 3), int($$cdef{b} / 3), $bg);
    } else {
      return rgb($$cdef{r}, $$cdef{g}, $$cdef{b});
    }
  } elsif ($opt{colordepth} >= 8) {
    if ($bg) {
      return $$cdef{ansibg} . $$cdef{bg8};
    } else {
      return $$cdef{ansifg} . $$cdef{fg8};
    }
  } elsif ($bg) {
    return $$cdef{ansibg};
  } else {
    return $$cdef{ansifg};
  }
}

sub gotoxy {
  my ($x, $y) = @_;
  return "\033[${y};${x}H";
}

#################################################################################################
#################################################################################################
###
###                             S U P P O R T    F U N C T I O N S :
###
#################################################################################################
#################################################################################################

sub debuglog {
  my ($msg) = @_;
  if ($opt{debug}) {
    open DEBUG, ">>", "debug.log";
    my $now = DateTime->now( time_zone => $opt{localtimezone} );
    print DEBUG $msg . "\n";
    close DEBUG;
  }
}

sub isare {
  my ($num) = @_;
  return "is" if $num == 1;
  return "are";
}

sub sgorpl { # Singular or plural, depending on number.
  my ($num, $noun, $pluralnoun) = @_;
  return $noun if $num == 1;
  return $pluralnoun || makeplural($noun);
}

sub makeplural {
  my ($noun) = @_;
  # Exceptions are handled by giving the asset an explicit plural when declaring it.
  # This function just has to handle the regular ones.
  if ($noun =~ /([sxz])$/) {
    return $noun . "es";
  } elsif ($noun =~ /([y])$/) {
    my $p = $noun;
    $p =~ s/y$/ies/;
    return $p;
  }
  return $noun . "s";
}

sub commalist {
  my (@item) = @_;
  if (2 >= scalar @item) {
    return join " and ", @item;
  }
  my $last = pop @item;
  my $rest = join ", ", @item;
  return join ", and ", $rest, $last;
}

sub shownum {
  my ($n) = @_;
  if ($n > 10 * 1000 * 1000 * 1000 * 1000 * 1000) {
    my $exp = 0;
    my $base = $n;
    while ($base > 1000) {
      $exp += 3;
      $base = int(($base + 500) / 1000);
    }
    while ($base >= 10) {
      $exp++;
      $base = int($base + 4.999) / 10;
    }
    return $base . "e+0" . $exp;
  } elsif ($n > 20 * 1000 * 1000 * 1000 * 1000) {
    my $t = int(($n + 500 * 1000 * 1000 * 1000) / (1000 * 1000 * 1000 * 1000));
    return $t . "t";
  } elsif ($n > 20 * 1000 * 1000 * 1000) {
    my $b = int(($n + 500 * 1000 * 1000) / (1000 * 1000 * 1000));
    return $b . "b";
  } elsif ($n > 20 * 1000 * 1000) {
    my $m = int(($n + 500000) / (1000 * 1000));
    return $m . "m";
  } elsif ($n > 20 * 1000) {
    my $m = int(($n + 500) / 1000);
    return $m . "k";
  } else {
    return $n;
  }
}

sub randomorder {
  my (@item) = @_;
  return map {
    $$_[0]
  } sort {
    $$a[1] <=> $$b[1]
  } map {
    [$_ => rand(65535) ]
  } @item;
}

sub uptime {
  local %ENV; delete $ENV{PATH};
  my $ut = `/usr/bin/uptime`;
  chomp $ut;
  $ut =~ /(up (?:\d+ \w+,?\s*\d*[:]?\d*(?: min)?)|\d+[:]?\d*(?: min)?),\s+(\d+\s+users?),\s+load average[:]\s+([0-9.]+),\s+([0-9.]+),\s+([0-9.]+)/;
  my ($up, $users, $loadone, $loadtwo, $loadthree) = ($1, $2, $3, $4, $5);
  if (wantarray) { return ($up, $users, $loadone, $loadtwo, $loadthree); }
  else { return $ut }
}

sub diffuse_scale {
  my ($v) = @_;
  return 0 if $v <= 0;
  my $ln = log($v * 1000);
  my $sqr = $ln * $ln;
  if ($sqr > 255) {
    return 255;
  } else {
    return int $sqr;
  }
}

sub notepad_unescape {
  my ($text) = @_;
  # TODO: improve on this.
  $text =~ tr/_/ /;
  return $text;
}

sub valuefromexpectations {
  my ($ev, $chances) = @_;
  # $ev is a percentage success probability per opportunity.
  # ($ev can be higher than 1 if a multiple outcome is possible from a single chance).
  # $chances is the number of opportunities.
  if ($chances < 100) {
    # base case, just iterate it out:
    my $total = 0;
    for (1 .. $chances) {
      $total += int($ev / 100);
      $total++ if (($ev % 100) > rand 100);
    }
    return $total;
  }
  # If we're doing a lot of instances, we don't wanna iterate it out,
  # because performance.  But we don't wanna just calculate it in a
  # single step, because there won't be enough variation.  We want the
  # output to center around the expectation but vary a bit, and we
  # want to accomplish this in no worse than O(log(n)) time for large
  # n.  (For small n, performance isn't a problem.)  The following
  # algorithm is not ideal, but it'll do for an idle game (which is my
  # way of saying I can't be bothered to look up or think up a really
  # correct algorithm at the moment).
  my $portion = int($chances / 10);
  my $result  = valuefromexpectations($ev, $chances - (9 * $portion));
  for (1 .. 9) {
    my $partial = int((($ev * $portion) + 50) / 100);
    if ($ev >= rand(100)) {
      $partial += int($partial / 10);
    } else {
      $partial -= int($partial / 10);
    }
    $result += $partial;
  }
  return $result;
}

