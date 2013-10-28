Diskwiper
=========

Diskwiper reclaims disk space from a used "raw" sparse image file

Description
-----------

The sparse disk formats don't automatically shrink. Let's say you fill 100GB of a sparse disk (we know this will roughly consume 100GB of physical disk space) and then delete some files so that you are only using 50GB. The physical disk space used should be 50GB, right? Wrong. Because the disk image doesn't shrink, it will always be 100GB on the file system even if the guest is now using less.

The below steps will detail how to get round this issue.

1. create same size file
2. copy MBR
3. make filesystem
4. copy each partition data to the new target drive

Usage
-----

```bsah
diskwiper SOURCE.RAW DEST.RAW
```

License
-------

[Beerware](http://en.wikipedia.org/wiki/Beerware) license.

If we meet some day, and you think this stuff is worth it, you can buy me a beer in return.
