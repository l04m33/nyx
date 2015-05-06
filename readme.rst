What's this?
############

It's Nyx, my experiment on Nim_. It's basically a static web server,
written with the asyncdispatch_ module, and serves the current
directory ('.') once started. It also contains a tiny framework for
writing dynamic web applications.

.. _Nim: http://nim-lang.org/
.. _asyncdispatch: http://nim-lang.org/docs/asyncdispatch.html

How's it going?
###############

Most basic server features, like request encapsulation and response
generating, are implemented. But due to a bug in Nim itself,
connection errors (EPIPE and alike) may be swallowed by the async
event loop.

I've patched Nim to correctly handle connection errors. Until the
patch is accepted by the Nim folks, you can get the patched version
here_.

.. _here: https://github.com/l04m33/Nim/tree/async_callback_issue_0412

What's the plan?
################

Well I don't have a plan, so please don't expect regular updates or
anything. But if you think it's funny enough, feel free to tell me
or fork it yourself.
