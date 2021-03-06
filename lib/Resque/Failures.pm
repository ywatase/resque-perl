package Resque::Failures;
use Moose;
with 'Resque::Encoder';
# ABSTRACT: Class for managing Resque failures

use Class::Load qw(load_class);
use Carp;

=attr resque

Accessor to the Resque object.

=cut
has resque => (
    is       => 'ro',
    required => 1,
    handles  => [qw/ redis key /]
);

=attr failure_class

Name of a class consuming the role 'Resque::Failure'.
By default: Resque::Failure::Redis

=cut
has failure_class => (
    is => 'rw',
    lazy => 1,
    default => sub {
        load_class('Resque::Failure::Redis');
        'Resque::Failure::Redis';
    },
    trigger => sub {
        my ( $self, $class ) = @_;
        load_class($class);
    }
);

=method throw

create() a failure on the failure_class() and save() it.

=cut
sub throw {
    my $self = shift;
    my $e = $self->create(@_);
    $e->save;
}

=method create

Create a new failure on the failure_class() backend.

=cut
sub create {
    my $self = shift;
    $self->failure_class->new( @_, resque => $self->resque );
}

=method count

How many failures was in all the resque system.

=cut
sub count {
    my $self = shift;
    $self->redis->llen($self->key('failed'));
}

=method all

Return a range of failures in the same way Resque::peek() does for
jobs.

=cut
sub all {
    my ( $self, $start, $count ) = @_;
    my $all = $self->resque->list_range(
        $self->key('failed'), $start, $count
    );
    $_ = $self->encoder->decode( $_ ) for @$all;
    return wantarray ? @$all : $all;
}

=method clear

Remove all failures.

=cut
sub clear {
    my $self = shift;
    $self->redis->del($self->key('failed'));
}

=method requeue

Requeue by index number.

Failure will be updated to note retried date.

=cut
sub requeue {
    my ( $self, $index ) = @_;
    my ($item) = $self->all($index, 1);
    $item->{retried_at} = DateTime->now->strftime("%Y/%m/%d %H:%M:%S");
    $self->redis->lset(
        $self->key('failed'), $index,
        $self->encoder->encode($item)
    );
    $self->resque->push(
        $item->{queue} => {
            class => $item->{payload}{class},
            args  => $item->{payload}{args},
    });
}

=method remove

Remove failure by index number in failures queue.

Please note that, when you remove some index, all
sucesive ones will move left, so index will decrese
one. If you want to remove several ones start removing
from the rightmost one.

=cut
sub remove {
    my ( $self, $index ) = @_;
    my $id = rand(0xffffff);
    my $key = $self->key('failed');
    $self->redis->lset( $key, $index, $id);
    $self->redis->lrem( $key, 1, $id );
}

__PACKAGE__->meta->make_immutable();
