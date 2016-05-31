# Swedish municipality web privacy analysis

This is a project from [Dataskydd.net](https://dataskydd.net) to analyze
certain privacy-related aspects of the websites of Sweden's 290
municipalities, using data generated by [OpenWPM](https://github.com/citp/OpenWPM),
and generate a pretty static website displaying the results.

The code wasn't written with public use in mind -- it can be rather
messy -- but rather to show exactly how the statistics were gathered
and generated.

## How to do it yourself
Get [OpenWPM](https://github.com/citp/OpenWPM) running.  For this
analysis we used revision `ba0eb6c`:

```
git clone https://github.com/citp/OpenWPM/
..
cd OpenWPM
...
git checkout ba0eb6c
```

It comes with an installation script (`install.sh`) tailored for Ubuntu
14.04. If you use something else, don't run the script, but have a look
at it and install whatever is necessary in the proper way for your
system.

Try running `demo.py` (note: Python 2, not 3!). If it seems to be
working, continue.

Clone this repository. `cd` into it. Copy two of its files to where you
installed OpenWPM (let say it's `~/openwpm`):

```
cp municipalities.txt openwpm_municipalities.py ~/openwpm
```

Then:

```
cd ~/openwpm
```

OpenWPM's `browse` command loads a specified URL and then tries to also
visit a specified number of links (from the same hostname as the URL)
from the initial page. Currently (v0.6.2), however, no links are visited
if the initial URL is a redirect. Therefore we need to first use curl to
figure out the *final URL* of each municipality website and put that in a
list (which we will later use as input to OpenWPM):

```
cat municipalities.txt|cut -d"|" -f1|xargs -I url_initial curl -Ls \
-o /dev/null -w '%{url_effective}\n' -A "Mozilla/5.0 (Windows NT 6.1; WOW64) \
AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.116 Safari/537.36" \
url_initial >> municipalities_final_urls.txt
```

(This might take a few minutes.)

Verify that we still have 290 URLs:

```
wc -l municipalities_final_urls.txt
290 municipalities_final_urls.txt
```

Before you start: When we first ran the test, more than a few of the sites would
crash OpenWPM's browser manager with a `StaleElementReferenceException`,
caused by the code that tries to extract (and use) internal links. In
rare instances it also happened that external links would be treated as
internal (a bug that will hopefully be fixed soon). A crude way of
dealing with the first issue, and a decent way to deal with the second,
is to change a couple of things in
`automation/Commands/utils/webdriver_extensions.py`.

First, install the [publicsuffixlist]() package (note: you might have to
use `pip2` depending on your system):

```
sudo pip install publicsuffixlist
```

Next, edit `automation/Commands/utils/webdriver_extensions.py` and add
this somewhere in the top of the file:

```
from publicsuffixlist import PublicSuffixList
```

Finally, comment out the following line in function `get_intra_links`:

```
domain = urlparse(url).hostname
links = filter(lambda x: (x.get_attribute("href") and x.get_attribute("href").find(domain) > 0 and x.get_attribute("href").find("http") == 0), webdriver.find_elements_by_tag_name("a"))
```

...and instead add the following (above `return links`):

```
psl = PublicSuffixList()
domain = psl.privatesuffix(urlparse(url).hostname)
links = []
for x in webdriver.find_elements_by_tag_name("a"):
    try:
        if x.get_attribute("href") and psl.privatesuffix(urlparse(x.get_attribute("href")).hostname) == domain and x.get_attribute("href").find("http") == 0:
            links.append(x)
        except:
            pass
```

Similarly we need to edit `automation/Commands/browser_commands.py`. In
function `browse_website`, comment out the following two lines:

```
links = get_intra_links(webdriver, url)
links = filter(lambda x: x.is_displayed() == True, links)
```

Instead, add:

```
links_initial = get_intra_links(webdriver, url)
links = []
for x in links_initial:
    try:
        if x.is_displayed() == True:
          links.append(x)
    except:
        pass
```

Run OpenWPM with our file:

```
python2 openwpm_municipalities.py
```

This might take many hours. The crawl data will end up in `data/crawl-data.sqlite`,
and OpenWPM output is logged to `data/openwpm.log`. Some sites will
probably time out. Re-run OpenWPM with just those sites (the existing
database will not be overwritten, just updated). You might want to
delete the entries of the failed sites first, though, as the site
generator doesn't handle multiple crawls of a website. E.g. if the sites
with `visit_id` 283 and 290 failed:

DELETE FROM http_response_cookies WHERE header_id IN (SELECT id FROM
http_responses WHERE visit_id IN (283, 290));
DELETE FROM http_request_cookies WHERE header_id IN (SELECT id FROM
http_requests WHERE visit_id IN (283, 290));
DELETE FROM http_responses WHERE visit_id IN (283, 290);
DELETE FROM http_requests WHERE visit_id IN (283, 290);
DELETE FROM profile_cookies WHERE visit_id IN (283, 290);
DELETE FROM site_visits WHERE visit_id IN (283, 290);

Next we have an Elixir program with two main modules: one for adding
some data to `crawl-data.sqlite`, and one for generating the website
(static HTML/CSS).

From your OpenWPM directory, copy `data/crawl-data.sqlite` to
`wherever-you-cloned-municipality-privacy/data`.

Make sure you have Erlang R18 and Elixir 1.2.x installed.

Go to the `municipality-privacy` directory. Install dependencies:

```
mix deps.get
```

The `SiteGenerator.AddStuff` module does various things:

* Adds `base_domain` column to table `http_requests` and updates each
  record (e.g. if column `url` has value `http://foo.bar.com/blah`,
  `base_domain` is set to `bar.com`).
* Adds various columns to table `site_visits` and sets them:
 * `municipality_name`: Municipality name (e.g. Uppsala), loaded from `municipalities.txt`
 * `scheme`: Whether the initial URL uses `http` or `https`
 * `hsts`: Value of Strict-Transport-Security if set, 0 if not set (or
   if set with `max-age=0`)
 * `referrer_policy`: Value of HTML meta referrer element if set, otherwise 0
 * `first_party_cookies`: Number of first-party cookies (i.e. same base
   domain as the site)
 * `third_party_cookies`: Number of third-party cookies (i.e. not same
   base domain as the site)
 * `third_party_requests`: Number of requests not made to base domain or
   one of its subdomains

The `SiteGenerator.Process` module generates a page for each municipality
as well as an index page with an overview, plus a few static pages, to
`web/kommuner`, where you'll also find various other things (CSS, JS,
images).

Run them:

```
mix run -e "SiteGenerator.AddStuff.start()"
mix run -e "SiteGenerator.Process.start()"
```

Or run within interactive elixir by prepending `iex -S`, e.g.,

```
iex -S mix run -e "SiteGenerator.AddStuff.start()"
```

## Credits (things distributed here)
  * [Bourbon](https://github.com/thoughtbot/bourbon), [Neat](https://github.com/thoughtbot/neat), [Bitters](https://github.com/thoughtbot/bitters), [Refills](https://github.com/thoughtbot/refills) (MIT license) by thoughtbot
  * [DataTables](https://datatables.net/) (MIT license) by SpryMedia Ltd
  * [jQuery](https://jquery.com/) (MIT license) by jQuery Foundation and other contributors
  * [Font Awesome](https://fortawesome.github.io/Font-Awesome/) (SIL OFL 1.1) by Dave Gandy
  * [Source Sans Pro](https://github.com/adobe-fonts/source-sans-pro) (SIL OFL 1.1) by Adobe Systems

## License
The following license applies to all non-third-party code:

    The MIT License (MIT)

    Copyright (c) 2016 Anders Jensen-Urstad

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER   IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.