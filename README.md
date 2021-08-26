# Mangadex Mark_Read

Just a simple ruby script/project for marking all chapters of a given manga chapter as Read, using Mangadex' official API.

## How to use

Well, you need ruby.

Then run `bundle install` to setup, and then `ruby mark_read.rb` with the necessary flags.

```help
mark_read.rb [OPTIONS]
  -h, --help:
    Show this help message
  -m, --mange_id [id]:
    The manga id to mark read. Must provide this or an explicit --url.
  -u, --username [name]:
    The username to login and retrieve a token with. Must also have a --password.
  -p, --password [password]:
    The password to login and retrieve a token with. Must also have a --username.
  -r, --url [url]:
    The URL of the manga to mark as read. Must provide either this or an explicit --manga_id.
  -l, --language [language_code]:
    The language to use when filtering chapter lookups. Defaults to 'en' if not provided.
  -t, --token [token]:
    The (bearer) session token to use. --username and --password are ignored if a token is provided.
  -d, --print-token:
    Before performing the requests, print out the session token being used. Can be provided as --token for subsequent invocations.
```

## Why

Mangadex was down for a while, so users may have read chapters on other sites. Translation groups are returning to the site and uploading again, so users' existing Follows lists will be out of date.

This script offers a quick way to "catch up" your Follow of a manga on mangadex to where you are on other sites.

## Caveats

* Mangadex has some rate limits, so this script will try to stay under them. But they could always change, and if they were significantly reduced, then you run the risk of getting throttled. User beware, etc.

* The chapters-related APIs are not quite consistent and a bit buggy, so you may have to run the script a couple of times with the same manga in order to fully mark it as read. It's otherwise idempotent, as far as I can tell.

* If you provide a username and password, the script logs in via the API and retrieves a session token. Otherwise, you can provide one directly. Session tokens can expire, so make sure to use a username and password once in a while.

* If you provide a `--url` instead of a `--manga_id`, then the script uses a simple regex to extract the manga id. This can be easier to use when marking a bunch of different manga as read. But if the URL format changes, this will break.

* No pagination/cursor support yet, so this may not work when a manga has hundreds of chapters.

* No true rate-limit handling (422 response or X-Ratelimit headers support) nor http redirect support.

