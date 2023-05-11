---
layout: post
title: "Firefox on Gentoo"
date: 2013-04-09 01:56
comments: true
categories: [gentoo, firefox, linux, cairo]
---

Before I'll start describing my adventure with firefox on gentoo, I'll clarify 
that firefox  is the only browser that I am using on my computers (well 
links/elinks/w3m for text browsing) and hopefully nothing is going to change my 
mind.  Why so?

For the past couple of years I have tried a bunch of alternatives and still believe
that firefox is the best choice.  When chrome(ium) became popular, a lot of people
switched to the glorious product of google, and it seems to me that the only
reason for that switch was a very good job of google's marketing department.
I found it quite cheeky when they started the overall development, as firefox was 
really the best on the market at that time, it was free, and it was way more popular
than anything else, that was probably something that google couldn't tolerate.
I always ask myself, wouldn't it be more productive, to join
the forces and to work on one product?  But then I kind of realise that if it
would happen we would really end up with monopoly in the world of browsers, 
which we don't want.

<!-- more-->
So, my main dissatisfaction with chromium and any webkit-based browser is that
they cannot fix freaking selection.  I can't show the picture, as I don't have
it installed, but whenever you select a text on a page with a complex layout,
selection goes faaaar beyond the text and selects some random areas of the
web-page.  You guys might say that I am picky, but this selection thing really
drives me nuts.  Can anyone fix it?

Another thing that nobody can mimic is
[Vimperator](http://www.vimperator.org/vimperator).  Yeah, there are some
plugins in chrome, but they are just funny.  Vimperator is not about adding
h,j,k shortcuts, seriously.  Look at the code if you don't believe me.

Finally, to my impression firefox is the best balance between speed and
resources.  Probably chrome can do regexps faster, but on my system it eats
noticeably more memory which  means that if you have more that one tab
open then most of the regexp effort goes down the drain because of memory 
overheads.  It is not really a scientific fact -- just my personal intuition.
May be you can configure this stuff, but after I used all my patience, 
firefox is still the winner.

## Running browsers on gentoo

Any browser is a critical application, which should work fast and shouldn't fail.
That is why I am and will compile all my browsers from source with the highest 
possible optimisations.  After one of recompilations I found out that sometimes 
the fonts were rendered bold in the places where they shouldn't be.  Mainly it 
happened when you scroll up and down with a wheel of your mouse.  See the picture 
below.

![Screenshot of the problem](/images/firefox-gentoo.png)

A couple of phrases in the middle of the wikipedia page look like if they are 
bold.  In the beginning I though that it is a problem of fontconfig and
infinality which I was actively configuring at that time.  Later I found out
that it was a problem in firefox itself.  The thing happens not very often and if
you select and deselect this bold text, the boldness goes away.  So in principle
you could even live with this thing, it is just quite annoying.

After some googling I found a
[bug](https://bugzilla.mozilla.org/show_bug.cgi?id=775203) 
in the firefox bugzilla marked as _fixed_.
Well, it definitely wasn't fixed on my system, and I am using
the latest releases.  Then I started to read the patches and
investigate what the hell is going on.  It turned out, that the problem had
something to do with the bug in cairo, and firefox people have their own
version of cairo, where they happily committed the fix.  So far so good, but
gentoo is linking against system cairo which does *not* have these changes.

> Anyone knows why?

Anyhow, after some more investigation I found a flag which links against cairo
from the firefox repository.  The flag is called `--disable-system-cairo` :)
So all you need to do is to add the following line to the e-build:
```
mozconfig_annotate '' --disable-system-cairo
```
recompile, and the problem happily goes away.  May be one day I will put
an overlays for that.  May be one day gentoo people will add this thing into
default tree.  Gentoo people, where are you? :)




