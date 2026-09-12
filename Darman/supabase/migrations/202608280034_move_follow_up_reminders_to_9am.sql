begin;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-follow-up-day-reminders';

-- pg_cron runs in UTC. 04:00 UTC is 09:00 in Pakistan (UTC+5).
-- Continue hourly through the day so temporary delivery failures can retry.
select cron.schedule(
  'send-darman-follow-up-day-reminders',
  '0 4-18 * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'darman_follow_up_project_url'
      ) || '/functions/v1/send-follow-up-day-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'darman_follow_up_publishable_key'
        )
      ),
      body := jsonb_build_object('scheduled_at', now()),
      timeout_milliseconds := 10000
    ) as request_id;
  $cron$
);

commit;
