package Deeme::Backend::DBI;

our $VERSION = '0.01';
use Deeme::Obj 'Deeme::Backend';
use DBI;
use Deeme::Utils qw(_serialize _deserialize);
use Carp 'croak';
use constant EVENT_TABLE     => "deeme_events";
use constant FUNCTIONS_TABLE => "deeme_functions";

#use Carp::Always;
has [qw(database _connection)];

sub new {
    my $self = shift;
    $self = $self->SUPER::new(@_);
    croak "No database string defined, database option missing"
        if ( !$self->database );
    $self->_connection( DBI->connect( @{ $self->database } ) );
    $self->_setup;
    return $self;
}

sub _table_exists {
    my $self   = shift;
    my $db     = $self->_connection;
    my $table  = shift;
    my @tables = $db->tables( '', '', '', 'TABLE' );
    if (@tables) {
        for (@tables) {
            next unless $_;
            return 1 if $_ eq $table;
        }
    }
    else {
        eval {
            local $db->{PrintError} = 0;
            local $db->{RaiseError} = 1;
            $db->do(qq{SELECT * FROM $table WHERE 1 = 0 });
        };
        return 1 unless $@;
    }
    return 0;
}

sub _setup {
    my $self = shift;
    #### Check event table, creating if not exists
    if ( !$self->_table_exists(EVENT_TABLE) ) {
        my $sql = "
        CREATE TABLE " . EVENT_TABLE . " (
          id       INTEGER PRIMARY KEY ,
          name    VARCHAR(100)
        )";
        $self->_connection->do($sql);
    }
    #### Check functions table, creating if not exists
    if ( !$self->_table_exists(FUNCTIONS_TABLE) ) {
        my $sql = "
        CREATE TABLE " . FUNCTIONS_TABLE . " (
          id       INTEGER PRIMARY KEY,
          function TEXT,
          events_id    INT(10) NOT NULL,
          once INT(1) NOT NULL,
        foreign key (events_id) references " . EVENT_TABLE . " (id)
        )";
        $self->_connection->do($sql);
    }
}

sub events_get {
    my $self        = shift;
    my $name        = shift;
    my $deserialize = shift // 1;
    my $sth         = $self->_connection->prepare( "
        SELECT
            f.function
        FROM
            " . FUNCTIONS_TABLE . " f
            INNER JOIN " . EVENT_TABLE . " e ON (f.events_id=e.id)
        WHERE e.name = ?
        " );
    $sth->execute($name);
    my $functions = [];
    while ( my $aref = $sth->fetchrow_arrayref ) {
        push( @{$functions}, @$aref );
    }

    #deserializing subs and returning a reference
    return undef if ( @{$functions} == 0 );
    return [ map { _deserialize($_) } @{$functions} ]
        if ( $deserialize == 1 );
    return $functions;
}    #get events

sub events_reset {
    my $self = shift;
    $self->_connection->do( "DELETE FROM '" . EVENT_TABLE . "'" );
    $self->_connection->do( "DELETE FROM '" . FUNCTIONS_TABLE . "'" );
}

sub events_onces {
    my $self = shift;
    my $name = shift;
    my $sth  = $self->_connection->prepare( "
        SELECT
            f.once
        FROM
            " . FUNCTIONS_TABLE . " f
            INNER JOIN " . EVENT_TABLE . " e ON (f.events_id=e.id)
        WHERE e.name = '" . $name . "'
        " );
    $sth->execute;
    my @onces = ();
    while ( my $aref = $sth->fetchrow_arrayref ) {
        push( @onces, @$aref );
    }

    #deserializing subs and returning a reference
    return @onces;
}    #get events

sub _event_name_to_id {
    my $self = shift;
    my $name = shift;
    my $sql  = 'SELECT id FROM ' . EVENT_TABLE . ' WHERE name = ? LIMIT 1';
    return $self->_connection->selectrow_array( $sql, undef, $name );
}

sub once_update {
    my $self     = shift;
    my $name     = shift;
    my $onces    = shift;
    my $event_id = $self->_event_name_to_id($name);
    my $dbh      = $self->_connection;
    my $sth      = $self->_connection->prepare( "
        SELECT
            id
        FROM
            " . FUNCTIONS_TABLE . "
        WHERE events_id = ?
        " );
    $sth->execute($event_id);
    my @functions_id = ();
    while ( my $aref = $sth->fetchrow_arrayref ) {
        push( @functions_id, @$aref );
    }
    $self->_connection->{AutoCommit} = 0;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 1;
    my $sql = "UPDATE " . FUNCTIONS_TABLE . "
    SET once=?  WHERE id=? ";

    warn "-- Something unpredictable happened, please contact the mantainer"
        if ( scalar @{$onces} != scalar(@functions_id) );

    my $end = @functions_id;
    eval {
        # insert a new link

        unless ( @functions_id == 0 ) {
            my $sth = $self->_connection->prepare($sql);
            $sth->execute( shift @{$onces}, shift @functions_id );
        }

        $dbh->commit();
    };

    if ($@) {
        warn "-- Error inserting the functions in Deeme: $@\n";
        $dbh->rollback();
    }
    $self->_connection->{AutoCommit} = 1;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 0;
}    #get events

sub event_add {
    my $self = shift;
    my $name = shift;
    my $cb   = shift;
    my $once = shift // 0;
    $cb = _serialize($cb);

    my $sql;
    if ( my $e_id = $self->_event_name_to_id($name) ) {
        $sql
            = 'SELECT id FROM '
            . FUNCTIONS_TABLE
            . ' WHERE events_id = ? AND function=? LIMIT 1';
        return $cb
            if $self->_connection->selectrow_array( $sql, undef, $e_id, $cb );
        $sql = "INSERT INTO " . FUNCTIONS_TABLE . " (events_id,function,once)
           VALUES(?,?,?)";
        my $sth = $self->_connection->prepare($sql);
        $sth->execute( $e_id, $cb, $once );
    }
    else {
        $sql = "INSERT INTO " . EVENT_TABLE . " (name)
           VALUES(?)";
        my $sth = $self->_connection->prepare($sql);
        $sth->execute($name);
        $sql = "INSERT INTO " . FUNCTIONS_TABLE . " (events_id,function,once)
           VALUES(?,?,?)";
        $sth = $self->_connection->prepare($sql);
        $sth->execute(
            $self->_connection->last_insert_id(
                undef, undef, FUNCTIONS_TABLE, undef
            ),
            $cb, $once
        );
    }
    return $cb;
}

sub event_delete {
    my $self     = shift;
    my $name     = shift;
    my $event_id = $self->_event_name_to_id($name);
    $self->_connection->{AutoCommit} = 0;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 1;
    eval {
        my $sth = $self->_connection->prepare(
            "DELETE
 FROM " . FUNCTIONS_TABLE . " WHERE events_id=?"
        );
        $sth->execute($event_id);
        $sth = $self->_connection->prepare(
            "DELETE
 FROM " . EVENT_TABLE . " WHERE id=?"
        );
        $sth->execute($event_id);
        $self->_connection->commit();
    };

    if ($@) {
        warn "-- Error inserting the functions in Deeme: $@\n";
        $self->_connection->rollback();
    }

    $self->_connection->{AutoCommit} = 1;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 0;
}    #delete event

sub event_update {
    my $self      = shift;
    my $name      = shift;
    my $functions = shift;
    my $serialize = shift // 1;
    return $self->event_delete($name) if ( scalar( @{$functions} ) == 0 );

    my $event_id = $self->_event_name_to_id($name);

#     my $sth         = $self->_connection->prepare( "DELETE ".FUNCTIONS_TABLE."
# FROM ".FUNCTIONS_TABLE." f
# INNER JOIN
# ".EVENT_TABLE." e on e.id = f.events_id
# and WHERE e.name='".$name."'" );
# $sth->execute;
    $self->_connection->{AutoCommit} = 0;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 1;
    eval {
        my $sth = $self->_connection->prepare(
            "DELETE
 FROM " . FUNCTIONS_TABLE . " WHERE events_id=?"
        );
        $sth->execute($event_id);
        my $sql
            = "INSERT INTO "
            . FUNCTIONS_TABLE
            . " (events_id,function,once)
           VALUES(?,?,?)";

        foreach my $f ( @{$functions} ) {
            if ( $serialize == 1 ) {
                $sth = $self->_connection->prepare($sql);
                $sth->execute( $event_id, _serialize($f), 0 );
            }
            else {
                $sth = $self->_connection->prepare($sql);
                $sth->execute( $event_id, $f, 0 );
            }

        }
        $self->_connection->commit();
    };

    if ($@) {
        warn "-- Error inserting the functions in Deeme: $@\n";
        $self->_connection->rollback();
    }

    $self->_connection->{AutoCommit} = 1;   # enable transactions, if possible
    $self->_connection->{RaiseError} = 0;

}    #update event

1;
__END__

=encoding utf-8

=head1 NAME

Deeme::Backend::Mango - MongoDB Backend using Mango for Deeme

=head1 SYNOPSIS

  use Deeme::Backend::Mango;
  my $e = Deeme->new( backend => Deeme::Backend::Mango->new(
        database => "deeme",
        host     => "mongodb://user:pass@localhost:27017",
    ) );

=head1 DESCRIPTION

Deeme::Backend::Mango is a MongoDB Deeme database backend using Mango.

=head1 AUTHOR

mudler E<lt>mudler@dark-lab.netE<gt>

=head1 COPYRIGHT

Copyright 2014- mudler

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Deeme>

=cut
