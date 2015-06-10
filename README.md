# NAME

DK Hostmaster pre-activation service demo client

# VERSION

This documentation describes version 2.0.X

# USAGE

    $ morbo -l https://*:3000 client.pl

Open your browser at:

    http://127.0.0.1:3000/

# INSTALLATION

This client requires a [Perl](http://en.wikipedia.org/wiki/Perl) interpreter.

In addition you need to install the [Mojolicious framework](http://mojolicio.us/).

```
$ curl -L https://cpanmin.us | perl - -M https://cpan.metacpan.org -n Mojolicious
```

Then you need to install the dependencies described below.

# DEPENDENCIES

The client is implemented using [Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite) in addition the following Perl modules are used all available from CPAN.

- [Mojolicious](https://metacpan.org/pod/Mojolicious) installed in the step above (MetaCPAN)
- [IO::Socket::SSL](https://metacpan.org/pod/IO::Socket::SSL) (MetaCPAN)
- [Time::HiRes](https://metacpan.org/pod/Time::HiRes) (MetaCPAN, in core since Perl version 5.7.3)
- [Digest](https://metacpan.org/pod/Digest) (MetaCPAN), in core since Perl version 5.7.3)

A `cpanfile` and related `cpanfile.snapshot` are included in the repository and can be used in conjunction with [Carton](https://metacpan.org/pod/Carton) if you want to evaluate the client without interfering with your existing Perl installation

```
$ carton

$ carton exec morbo -l https://*:3000 client.pl
```

In addition to the Perl modules, the client uses Twitter Bootstrap and hereby jQuery. These are automatically downloaded via CDNs and are not distributed with the client software.

- http://getbootstrap.com/

# SEE ALSO

The main site for this client is the [Github repository](https://github.com/DK-Hostmaster/preact-demo-client-mojolicious).

For information on the service, please refer to [the specification](https://github.com/DK-Hostmaster/preactivation-service-specification) from DK Hostmaster or [the service main page with DK Hostmaster](https://www.dk-hostmaster.dk/english/technical-administration/tech-notes/pre-activation/).

# COPYRIGHT

This software is under copyright by DK Hostmaster A/S 2015

# LICENSE

This software is licensed under the MIT software license

Please refer to the LICENSE file accompanying this file.
