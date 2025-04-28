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

Sadly, a fully automated migration as part of a Mastodon update is not
possible. This is mainly due to different scenarios needing different
approaches.

After having discussed this with some server administrators, we have
identified two main scenarios:

1. Dedicated Redis instances that use namespaces, even though they do
   not strictly need to. Sometimes this in an artifact of a formerly
   shared installation, or just because it was there as an option. In
   this case it is sufficient to just strip the namespace from all the
   keys in Redis.
2. A shared Redis instance used by more than one Mastodon installation.
   In this case we recommend to use a dedicated Redis instance per
   Mastodon installation, which means you will need to move keys to
   another Redis instance and then rename them.

> [!NOTE]
> If you have read the article linked above you might wonder about
> another option: Instead of having dedicated Redis instances, one could
> also consider using Redis' built-in mechanism for data separation,
> databases. Please see below for an explanation why we do not currently
> consider this to be a viable option.

This document is meant to help server administrators to perform a
migration in one of the two scenarios mentioned above. It should also
give you an idea what to do if your setup does not match one of those
perfectly. But feel free to reach out if you need help and/or think this
document is missing something.

> [!CAUTION]
> This document is a work in progress. *DO NOT* use anything mentioned
> here on a production system. But if you have a way to recreate your
> production environment on a separate test machine or cluster and want
> to try it out there, we would love to hear your feedback.

## Performing Migrations

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

### Case 1: Keep Redis Database, Only Remove Namespace

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
script to do so is [rename.rb](rename.rb) in this repository.

You can copy it into your Mastodon code directory (e.g.
`/home/mastodon/live`), make sure your Mastodon services are stopped and
run it like this:

```sh
RAILS_ENV=production bin/rails runner rename.rb
```

After this, edit your `.env.production` and depending on your current
setup either:

1. Rename `REDIS_NAMESPACE` to `ES_PREFIX` if (and only if) you are
   using ElasticSearch and did not have `ES_PREFIX` configured. (In
   this case `REDIS_NAMESPACE` was used as the default for prefixes
   in ElasticSearch.) OR
2. Remove `REDIS_NAMESPACE` altogether if not using ElasticSearch *or*
   if you already have a `ES_PREFIX` variable set.

Save your configuration and restart all Mastodon services.

### Case 2: Move Redis Keys To A Dedicated Redis Instance

Redis makes it relatively easy to start different instances even on the
same server. Just use a different port for each instance and you should
be good. The memory overhead for running another instance of redis is
very small.

So if you currently share a single redis instance between different
installations of Mastodon, spinning up a separate, dedicated instance for
each Mastodon installation is a good solution.

> [!TIP]
> While you are at it you should also consider running a separate redis
> instance just for cache, a setup we recommend for every instance that
> has more than a handful of users. Of course you should only attempt
> this after having migrated keys successfully.

In this case you need to move keys from one Redis instance to another,
then rename them. An example script to do so is [move.rb](move.rb) in
this repository.

You can copy it into your Mastodon code directory (e.g.
`/home/mastodon/live`), make sure your Mastodon services are stopped and
run it like this:

```sh
NEW_REDIS_URL=<Redis URL> RAILS_ENV=production bin/rails runner move.rb
```

Make sure to set `NEW_REDIS_URL` to an Redis connection URL pointing to
your new, dedicated Redis instance. Also make sure your old Redis
instance can actually reach this URL.

After this, update your `env.production` file to point to the new,
dedicated Redis instance and depending on your current setup, either:

1. Rename `REDIS_NAMESPACE` to `ES_PREFIX` if (and only if) you are
   using ElasticSearch and did not have `ES_PREFIX` configured. (In
   this case `REDIS_NAMESPACE` was used as the default for prefixes
   in ElasticSearch.) OR
2. Remove `REDIS_NAMESPACE` altogether if not using ElasticSearch *or*
   if you already have a `ES_PREFIX` variable set.

Save your configuration and restart all Mastodon services.

## Why Not Redis Databases?

Redis databases are a built-in way to isolate different key namespaces
from each other. It is one of the options mentioned in the Sidekiq
article linked to above.

While this looks good as a way to share a single Redis instance between
different Mastodon installations on the surface, there are a couple of
problems with it.

The most obvious one is that while databases offer real isolation of key
namespaces, channels used for Publish/Subscribe still share a single,
global namespace. Mastodon uses Publish/Subscribe for its streaming
server, so databases will not work here.

We thought about providing different workarounds for this, but then were
made aware of [this comment here by a Redis
developer](https://github.com/redis/redis/issues/8099#issuecomment-741868975)
saying that the Redis core team does *not* recommend this setup.

With that in mind we decided to not built a half-baked solution based on
a mechanism that is not recommended by upstream developers.

Databases may still become an alternative in the future, though: The
Valkey team is currently contemplating offering full isolation between
databases, including pub/sub. See [this issue here](https://github.com/valkey-io/valkey/issues/1868)
for details.


