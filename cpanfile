requires "HTTP::Headers::Fast" => "0";
requires "Log::Any" => "0";
requires "Measure::Everything" => "0";
requires "Plack::Middleware" => "0";
requires "Plack::Request" => "0";
requires "Plack::Util::Accessor" => "0";
requires "Time::HiRes" => "0";
requires "parent" => "0";
requires "perl" => "5.010";
requires "strict" => "0";
requires "warnings" => "0";

on 'build' => sub {
  requires "Module::Build" => "0.28";
};

on 'test' => sub {
  requires "Test::More" => "0";
};

on 'configure' => sub {
  requires "Module::Build" => "0.28";
};