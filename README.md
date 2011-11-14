This library is an API wrapper for the [Vindicia](http://vindicia.com/) payment gateway.

# Dependencies

* nokogiri
* savon

# Usage

Call either `Vindicia.authenticate` to pass auth credentials or use `Vindicia.configure` which yields a block.  For example:

``` ruby
Vindicia.configure do |config|  
  config.login = 'login'  
  config.password = 'password'  
  config.environment = 'prodtest'  
end
```

Calling `configure` triggers the `bootstrap` method which will automatically generate all of the APIs for your specified version (or default of 3.6)

After that, all APIs are classes within the Vindicia namespace, with their soap actions as method calls


# Credits

This library was forked from [AvidLifeMedia/vindicia](https://github.com/AvidLifeMedia/vindicia) and heavily modified.
It was influenced by the work of [steved555/vindicia-api](https://github.com/steved555/vindicia-api).
