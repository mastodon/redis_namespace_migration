# Migrate Away From Using Redis Namespaces For Mastodon

## Background

Mastodon has supported using a dedicated namespace for keys in redis for
a long time. The idea was that several applications (or instances of
Mastodon) could share a single redis database this way.

We soft-deprecated this option in Mastodon 4.3, mainly because newer
versions of [sidekiq](https://github.com/mperham/sidekiq) no longer
support it.

> [!NOTE]
> `sidekiq`'s author wrote a bit about why he thinks namespaces in redis
> are a bad idea in his article
> [Storing Data With Redis](https://www.mikeperham.com/2015/09/24/storing-data-with-redis/)
> and in his article about
> [Migrating from redis-namespace](https://www.mikeperham.com/2017/04/10/migrating-from-redis-namespace/).
> We will get back to this article later.

Keeping this option means we cannot update `sidekiq` which
has since released two new major versions. Even worse, due to
`sidekiq`'s version requirements for some transitive dependencies, this
holds back updates of other dependencies as well.

This reduces Mastodon's security, keeps us from adding some "free"
features gained by updating dependencies and holds back future feature
development in Mastodon.

While we know this is very unfortunate for server admins that use this
option, given the reasons above we do not think we have a choice other
than to remove it from Mastodon.

Sadly, a fully automated migration for affected server administrators
does not seem to be possible. And we struggle to find a "one size fits
all" solution, mainly because we never used this option ourselves and do
not know how and why exactly it is used by others.

This document is meant to help server administrators to perform a
migration in a half-automated way and to collect feedback on the process
and on scenarios that we may not have considered.

> [!CAUTION]
> This document is a work in progress. *DO NOT* use anything mentioned
> here on a production system. But if you have a way to recreate your
> production environment on a separate test machine or cluster and want
> to try it out there, we would love to hear your feedback.

## Migration approaches

If you use a `REDIS_NAMESPACE` you cannot migrate away from that without
some downtime. The exact downtime depends on the number of keys you have
in redis and where you migrate to. We tested a very simple case with
500,000 tiny key/value pairs which took a couple of seconds, but this
may vary *a lot* on real-world production data, so you should probably
test this on your infrastructure with a dump of the redis database.

The process is always roughly the same:

1. Stop *all* Mastodon services (web, sidekiq, streaming).
2. Migrate redis keys to not use namespaces.
3. Update Mastodon config (no more namespaces, possibly different redis
   location)
4. Restart Mastodon services

The difference lies in where to migrate redis keys to.

### Case 1: Keep redis Database, Only Remove Namespace

Redis namespaces were introduced to share a single redis database with
other applications. In the most simple case, you do not (or no longer)
need this. This would apply if

* You only ever used this redis database for a single Mastodon instance
  to begin with, or
* You used to share the redis database with other software or other
  instances of Mastodon, but no longer do so, or
* You share the redis database with other applications but can migrate
  those away to use something else before starting the Mastodon
  migration.

In this case you only need to rename the keys in redis. An example
script to do so is [rename\_ns.rb](remove_ns.rb) in this repository.

You can copy it into your Mastodon code directory (e.g.
`/home/mastodon/live`), make sure your Mastodon services are stopped and
run it like this:

```sh
RAILS_ENV=production bin/rails runner remove_ns.rb
```

After this, remove `REDIS_NAMESPACE` from your `.env.production`
configuration file and restart your Mastodon services.

### Case 2: Move redis Keys To Different redis Database

If you really can only use a single instance of redis but still need to
share this with other applications, using a separate redis database
could be an option. By default, redis has 16 different databases
(numbered 0-15) that each have a totally separate key space.

To migrate keys in this scenario you would need to amend the script from
this repository and move the key to the other database before renaming
it. This can be achieved with the [`MOVE`
command](https://redis.io/docs/latest/commands/move/).

When this is finished you need to edit your `.env.production`
configuration and use `REDIS_URL` to point to the other database, e.g.
`REDIS_URL=redis://localhost:6379/4` to use the database numbered `4`.

> [!WARNING]
> redis does not recommend using databases to share one instance between
> different apps. This is probably the least robust option and should be
> avoided if at all possible.

> [!CAUTION]
> There is one huge caveat with this solution: While databases have a
> separate keyspace, the names of channels for pub/sub in redis always
> share one global namespace. This means you might not be able to share
> a single redis instance with different apps using pub/sub and you
> should never share it between different instances of Mastodon.

### Case 3: Move redis Keys To A Dedicated redis Instance

Redis makes it relatively easy to start different instances even on the
same server. Just use a different port for each instance and you should
be good. The memory overhead for running another instance of redis is
very small.

So if you currently share a single redis instance between different
apps, spinning up a separate, dedicated instance for Mastodon might be a
good solution.

> [!TIP]
> While you are at it you should also consider running a separate redis
> instance just for cache, a setup we recommend for every instance that
> has more than a handful of users. Of course you should only attempt
> this after having migrated key names successfully.

Just like with the last scenario the migration in this case would
require some changes to the script above. Instead of renaming keys, you
should first move the keys to the new redis instance. This can be
achieved with the
[`MIGRATE` command](https://redis.io/docs/latest/commands/migrate/).
This will probably take a long time.

When this is finished you should use the unmodified script to rename the
keys.

## Namespaces And Multiple redis Instances

The approaches outlined above all expect that you run a single instance of
redis. Mastodon allows (and recommends) to use separate redis instances
for different use-cases. At least the cache redis should be separate
from the app and sidekiq redis.

We do not expect anyone to use separate redis instances *and*
namespaces, but if you do please let us know.

The migration process is not much different, except that will have to
run the migration script once against each redis instance.
