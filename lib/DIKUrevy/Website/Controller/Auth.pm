package DIKUrevy::Website::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller';
use utf8;

use DIKUrevy::Email;

use Mojo::Template;
use Mojo::JWT;


our $_email_match = qr/^.*\@.*$/;

sub login {
    my $self = shift;
    return $self->render('auth/login');
}

sub login_submit {
    my $self = shift;

    my $v = $self->validation;
    $v->required('username');
    $v->required('password');

    if ($v->has_error || $v->csrf_protect->has_error('csrf_token')) {
        $self->show_error('Udfyld både navn og løsen.');
        return $self->login();
    }

    unless ($self->helpers->authenticate( $v->output->{username}, $v->output->{password} )) {
        $self->show_error('Ugyldigt login.');
        return $self->login();
    }


    return $self->redirect_to('frontpage');
}

sub logout {
    my $self = shift;
    $self->helpers->logout;
    return $self->redirect_to('frontpage');
}

sub create_user {
    my $self = shift;
    return $self->render('auth/create_user');
}

sub _user_validator {
    my $self = shift;

    my $v = $self->validation;
    $v->required($_) for qw/username password realname phone/;
    $v->required('email')->like($_email_match);

    return $v;
}

sub create_user_submit {
    my $self = shift;

    my $v = $self->_user_validator();

    if ($v->has_error || $v->csrf_protect->has_error('csrf_token')) {
        $self->show_error('Fejl i formularen.');
        return $self->create_user();
    }

    my $user = DIKUrevy::User->retrieve( { username => $v->output->{username} } );
    if ($user) {
        $self->show_error('Brugernavnet er allerede taget.');
        return $self->create_user();
    }

    $user = DIKUrevy::User->new( %{ $v->output } );
    $user->set_password($self->param('password'));
    $user->save;

    my $mail = $self->render_to_string(template => 'auth/mail_created', user => $user, layout => undef)->to_string;
    DIKUrevy::Email->send_mail(
        to      => $self->config('admin_mail'),
        subject => "Ny bruger oprettet på websiden: " . $user->username,
        body    => $mail,
    );

    $self->show_message('Din bruger er oprettet, men skal først bekræftes af revybosserne. Når dette er sket vil du få en mail.', flash => 1);
    return $self->redirect_to('frontpage');
}

sub random_password() {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9', '@%$#&+*');
    return join('', map { $chars[rand @chars] } 1..16);
}

sub new_password {
    my $self = shift;

    my $jwt = $self->req->query_params->param('jwt');
    if ($jwt) {
        my $secret = $self->config('secrets')->[0];
        my $claims;
        eval { $claims = Mojo::JWT->new(secret => $secret)->decode($jwt); };
        if ((! $claims) || (time() > $claims->{'exp'})) {
            $self->show_error('Ugyldigt løsen-link.', flash => 1);
            return $self->redirect_to('frontpage');
        }
        else {
            my $user = DIKUrevy::User->retrieve( { id => $claims->{'id'} } );
            my $new_password = random_password();
            $user->set_password($new_password);
            $user->save;
            $self->show_message('Du kan nu logge ind med dit nye løsen: '
                                . $new_password,
                                flash => 1);
            return $self->redirect_to('frontpage');
        }
    }
    else {
        return $self->render('auth/new_password');
    }
}

sub new_password_submit {
    my $self = shift;

    my $v = $self->validation;
    $v->required('email_address')->like($_email_match);

    if ($v->has_error || $v->csrf_protect->has_error('csrf_token')) {
        $self->show_error('Udfyld email-adresse.');
        return $self->new_password();
    }

    my $users = DIKUrevy::User->fetch( { email => $v->output->{email_address} } );
    if (@$users == 1) {
        my $user = $users->[0];
        my $user_id = $user->{'id'};
        my $secret = $self->config('secrets')->[0];
        my $in_one_hour = time() + 60 * 60;
        my $jwt = Mojo::JWT->new(secret => $secret,
                                 expires => $in_one_hour,
                                 claims => {id => $user_id})->encode;

        my $mail = $self->render_to_string(template => 'auth/new_password_email',
                                           jwt => $jwt,
                                           layout => undef)->to_string;
        DIKUrevy::Email->send_mail(
            to      => $v->output->{email_address},
            subject => "Få et nyt løsen til dikurevy.dk",
            body    => $mail,
            );
    }

    # Show this message even if the email address is invalid, to defend against
    # targeted data extraction.
    $self->show_message('Vi har sendt dig instruktioner til at lave et nyt løsen.',
                        flash => 1);
    return $self->redirect_to('frontpage');
}

sub edit_user {
    my $self = shift;
    my $user = $self->current_user;
    for my $f (qw/username password realname phone email/) {
        $self->param($f, $user->$f) if (! $self->param($f) && $user->$f);
            $self->param($f, $user->$f) if (! $self->param($f) && $user->$f);}
    return $self->render('auth/edit_user');
}

sub edit_user_submit {
    my $self = shift;

    my $v = $self->_user_validator();

    if ($v->has_error || $v->csrf_protect->has_error('csrf_token')) {
        $self->show_error('Fejl i formularen.');
        return $self->edit_user();
    }

    my $user = $self->current_user;
    for my $f (qw/username realname phone email/) {
        $user->$f( $self->param($f) ) if defined($self->param($f));
    }

    $user->set_password($self->param('password'));

    $user->save();

    $self->show_message('Din bruger er hermed opdateret.', flash => 1);
    $self->redirect_to('edit_user');
}

1;
