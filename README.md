This library is an API wrapper for the [Vindicia][] payment gateway.

# Dependencies

As of the 0.2.0 release, this gem targets Ruby 1.9.

It requires the [savon][] SOAP client library, and will use [httpclient][] if present (otherwise just using net/http).

# Usage

Firstly, call `Vindicia.authenticate` with your login, password, and target environment. These values will remain cached for all subsequent calls.

After that, all soap calls are methods on classes in the Vindicia namespace, taking either hashes or other instances as arguments. For example,

      account, created = Vindicia::Account.update({
        :merchantAccountId => "user42",
        :name => "bob"
      })

Almost all interaction is dynamically driven by the content of the WSDL files, but there are two special cases.

`Vindicia::Thing#ref` will return a minimal hash for lookups in subsequent calls. So after creating a new `Account`, you can substitute `account.ref` in a purchase call, rather than sending the entire object back over the wire.

`Vindicia::Thing.find` is a convenience method to call the appropriate method to look up the object by merchant id, simply to reduce redundancy.

# Development

Developers looking to build upon this gem will need to install [isolate][], which will sandbox installation of savon, [rspec][], and [jeweler][] in `./tmp`.

To run the specs, you'll need to copy `authenticate.example.rb` to `authenticate.rb` and fill in your own account information. Additionally, a number of specs depend on existing data in my test account, which should probably be fixed at some point (probably with a rake task to populate the test environment).

# Known Issues

HTTPI (a savon dependency) is _really_ chatty logging to stdout, and I haven't figured out a good way to mute it.

WSDL files are being live-downloaded every run. It'd be nice to cache them locally.


[Vindicia]: http://www.vindicia.com/
[savon]: https://github.com/rubiii/savon
[httpclient]: https://github.com/nahi/httpclient
[isolate]: https://github.com/jbarnette/isolate
[rspec]: https://rspec.info/
[jeweler]: https://github.com/technicalpickles/jeweler
