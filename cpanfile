requires "Class::Usul" => "v0.72.0";
requires "Cpanel::JSON::XS" => "3.0115";
requires "Crypt::Eksblowfish" => "0.009";
requires "DBIx::Class" => "0.08204";
requires "DBIx::Class::Helpers" => "2.023005";
requires "DBIx::Class::InflateColumn::Object::Enum" => "0.04";
requires "DBIx::Class::TimeStamp" => "0.14";
requires "Daemon::Control" => "0.001006";
requires "Data::Validation" => "v0.23.0";
requires "Exporter::Tiny" => "0.042";
requires "File::DataClass" => "v0.68.0";
requires "HTTP::Message" => "6.06";
requires "JSON::MaybeXS" => "1.003005";
requires "Moo" => "2.000001";
requires "Plack" => "1.0036";
requires "Plack::Middleware::Debug" => "0.16";
requires "Plack::Middleware::Deflater" => "0.08";
requires "Plack::Middleware::FixMissingBodyInRedirect" => "0.12";
requires "Plack::Middleware::LogErrors" => "0.001";
requires "Plack::Middleware::Session" => "0.21";
requires "Starman" => "0.3000";
requires "Try::Tiny" => "0.22";
requires "Type::Tiny" => "1.000005";
requires "Unexpected" => "v0.43.0";
requires "Web::Components" => "v0.5.0";
requires "Web::Components::Role::TT" => "v0.5.0";
requires "Web::ComposableRequest" => "v0.7.0";
requires "Web::Simple" => "0.030";
requires "local::lib" => "2.000015";
requires "namespace::autoclean" => "0.26";
requires "perl" => "5.010001";
requires "strictures" => "2.000000";
recommends "CSS::LESS" => "v0.0.3";

on 'build' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};

on 'test' => sub {
  requires "File::Spec" => "0";
  requires "Module::Build" => "0.4004";
  requires "Module::Metadata" => "0";
  requires "Sys::Hostname" => "0";
  requires "Test::Requires" => "0.06";
  requires "version" => "0.88";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};
