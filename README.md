# lua-resty-hyperloglog

`lua-resty-hyperloglog` is hyperloglog for openresty.

Table of Contents
=================
* [Status](#status)
* [Synopsis](#Synopsis)
* [Methods](#methods)
    * [new](#new)
    * [insert](#insert)
    * [count](#count)
    * [merge](#merge)
    * [close](#close)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Status
======

This library is still under early development and is still experimental.

Synopsis
========

```nginx

http {

    ...

    lua_shared_dict hll_count 10m;

    init_by_lua_block {
        local hll = require "resty.hyperloglog"
        h = hll.new("hll_count", 12)
    }

    server {
        listen 8080;

        location / {
            access_by_lua_block {
                h:add(ngx.var.uri)
            }

            ...
        }

        location = /stats {
            content_by_lua_block {
                ngx.print("count:", h:count())
                ngx.exit(ngx.HTTP_OK)
            }
        }
    }
}


```

[Back to TOC](#table-of-contents)

Methods
=======

new
---
`syntax: h, err = hll.new(name, log2m)`

Create a hyperloglog object with 2^log2m bucket. Returns `nil` on error.


insert
------
`syntax: h:insert(str)`

Insert a string to hyperloglog object.

count
-----
`syntax: c = h:count()`

Returns the cardinality of the hyperloglog object.

merge
-----
`syntax: ok, err = h:merge(h2)`

Merge another hyperloglog object(h2) into h. Returns `false` on error.

close
-----
`syntax: h:close()`

Close the hyperloglog object.


[Back to TOC](#table-of-contents)

Author
======

wenqiang li(vislee)

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD License.

Copyright (C) by vislee.

All rights reserved.

[Back to TOC](#table-of-contents)

