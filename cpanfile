requires 'DBI';
requires 'Deeme';
requires 'Deeme::Obj';
requires 'Deeme::Utils';
requires 'feature';

on configure => sub {
    requires 'Module::Build::Tiny', '0.035';
    requires 'perl', '5.008005';
};

on test => sub {
    requires 'Carp::Always';
    requires 'Test::More';
    requires 'Deeme::Backend::SQLite';
    requires 'DBD::SQLite';
};
