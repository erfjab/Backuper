**Backuper** is an automated backup script with full customization options and support for multiple platforms.  

## Supported Platforms  

- [x] **Gmail**  
- [x] **Telegram**  
- [x] **Discord**  

## Key Features  

- **Customizable remarks**  
- **Automated scheduling**  
- **Multi-template support**  
- **Add/remove custom directories**  
- **Send backups with no size limits**  
- **Set a password for backup files**  
- **User-friendly interface**  
- **Clear old backups**  
- **Include date and time in file names**  
- **Optimized for performance**  

## Supported Templates  

- [x] **X-ui**
- [x] **Remnawave**
- [x] **Marzban**

## Installation  

To install the latest version, run:  

```bash
sudo bash -c "$(curl -sL https://github.com/dnrshtnk/Backuper/raw/master/backuper.sh)"
```  

## Backup and sending schedules

Choose daily or weekly schedules and a time separately for archive creation and
delivery. Times use the server's local timezone. For example, create a backup
every day at 02:00 and send it every Sunday at 03:00. Schedule delivery after
the backup if both run on the same day.

Each successful backup is kept in `/root/._backuper_<remark>_archives/`. Delivery
sends the most recent completed archive without creating a new backup. The
total size of all archive parts is checked against 10 MiB (10,485,760 bytes).
If it is larger, a text notification is sent instead and the archive remains
on the server. After successful delivery or notification, older archives are
deleted and only the latest is kept. If delivery fails, no archives are deleted.

To update an existing installation, run the current installer and choose menu
option **5**, then select the existing backup and set both schedules. Existing
archive, database and delivery settings are preserved; its old cron entry is
replaced. A copy of the original generated script is saved beside it with the
suffix `.before-separated-schedules`. Unrecognized script formats are left
unchanged. Run the generated script with `backup` or `send` to do either task
manually.
