# NAME

Deeme::Backend::DBI - DBI Backend for Deeme

# SYNOPSIS

    use Deeme::Backend::DBI;
    my $e = Deeme->new( backend => Deeme::Backend::DBI->new(
          database => ["dbi options","other options"],
      ) );
    #or
    my $Backend = Deeme::Backend::DBI->new(
      database => "dbi:SQLite:dbname=/path/to/sqlite.db",
    );

# DESCRIPTION

Deeme::Backend::DBI is a DBI Deeme database backend.

# AUTHOR

mudler <mudler@dark-lab.net>

# COPYRIGHT

Copyright 2014- mudler

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[Deeme](https://metacpan.org/pod/Deeme)
