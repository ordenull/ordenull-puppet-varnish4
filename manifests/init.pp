## = Class: varnish4
#
# This is the main varnish class for varnish4
#
# == Parameters
#
# [*start_service*]
#   Enables the main varnish service
#   Default: true.
#
# [*start_ncsa*]
#   Enables the access log service
#   Default: true.
#
# [*start_log*]
#   Enables the debug log service
#   Default: true.
#
# [*instance*]
#   Instance name.
#   Default: "default"
#
# [*nfiles*]
#   Maximum number of open files (for ulimit -n)
#   Default: 131072
#
# [*memlock*]
#   Locked shared memory (for ulimit -l)
#   Default log size is 82MB + header
#
# [*nprocs*]
#   Maximum number of threads (for ulimit -u)
#   Default: "unlimited"
#
# [*vcl_conf*]
#   Main configuration filename
#   Default: /etc/varnish/default.vcl
#
# [*listen_address*]
#   Address to bind the main process to
#   Default: 0.0.0.0
#
# [*port*]
#   Port to bind the main process to. Typically changed to 80.
#   Default: 6081
#
# [*admin_listen_address*]
#   Address to bind the admin interface to
#   Default: 127.0.0.1
#
# [*admin_listen_port*]
#   Port on which to listen for admin commands
#   Default: 6082
#
# [*min_threads*]
#   The minimum number of worker threads to start
#   Default: 1
#
# [*max_threads*]
#   The Maximum number of worker threads to start
#   Default: 1000
#
# [*thread_timeout*]
#   Idle timeout for worker threads, in seconds
#   Default: 120
#
# [*secret*]
#   The password user by varnish admin.
#   If blank, it's untouched and left to whatever the distro package sets.
#   If 'auto' a random password is generated
#
# [*secret_file*]
#   Shared secret file for admin interface
#   Default: /etc/varnish/secret
#
# [*ttl*]
#   Default TTL used when the backend does not specify on, in seconds
#   Default: 120
#
# [*storage*]
#   Cache storage type and size
#   Default: file,/var/lib/varnish/$INSTANCE/varnish_storage.bin,1G
#   Specify 'malloc,1GB' to keep the cache in memory
#
# [*vcl_source*]
#   The source of the configuration file
#   Default: empty
#
# [*ncsa_log_file*]
#   Acess log filename
#   Default: /var/log/varnish/varnishncsa.log
#
# [*ncsa_options*]
#   Options to the access lgo daemon
#   Default: empty
#
# == Examples
#
#   class { 'varnish4':
#    start_service => true,
#    start_ncsa    => true,
#    start_log     => true,
#    storage       => 'malloc,500MB',
#    port          => 80,
#    vcl_source    => 'puppet:///varnish/api.vcl',
#  }
#
class varnish4 (
  $start_service        = true,
  $start_ncsa           = false,
  $start_log            = false,
  $instance             = 'default',
  $vcl_conf             = '/etc/varnish/default.vcl',
  $vcl_source           = undef,
  $nfiles               = 131072,
  $memlock              = 82000,
  $listen_address       = '0.0.0.0',
  $port                 = '6081',
  $admin_listen_address = '127.0.0.1',
  $admin_listen_port    = '6082',
  $min_threads          = '1',
  $max_threads          = '1000',
  $thread_timeout       = '120',
  $secret               = 'auto',
  $secret_file          = '/etc/varnish/secret',
  $storage              = "file,/var/lib/varnish/$instance/varnish_storage.bin,1G",
  $ttl                  = 120,
  $ncsa_log_file        = '/var/log/varnish/varnishncsa.log',
  $ncsa_options         = '',
) {

  #############################################
  ## Install the latest varnish package      ##
  #############################################
  package { 'apt-transport-https':
    ensure => present,
  }

  file { 'repository-config':
    name    => '/etc/apt/sources.list.d/varnish-cache.list',
    mode    => 644,
    owner   => root,
    group   => root,
    content => "deb https://repo.varnish-cache.org/ubuntu/ precise varnish-4.0\n",
  }

  exec { 'add-key':
    command => '/usr/bin/curl https://repo.varnish-cache.org/ubuntu/GPG-key.txt | /usr/bin/apt-key add -',
    unless  => '/usr/bin/apt-key export C4DEFFEB',
  }

  exec { "apt-update":
    command => "/usr/bin/apt-get update",
    onlyif  => "/bin/sh -c '[ ! -f /var/cache/apt/pkgcache.bin ] || /usr/bin/find /etc/apt/* -cnewer /var/cache/apt/pkgcache.bin | /bin/grep . > /dev/null'",
    require => [ Exec['add-key'], File['repository-config'], Package['apt-transport-https'] ]
  }

  package { 'varnish':
    ensure  => present,
    require => Exec['apt-update'],
  }

  #############################################
  ## Create the shared secret                ##
  #############################################
  $real_varnish_secret = $secret ? {
    ''      => '',
    'auto'  => fqdn_rand(100000000000),
    default => $secret,
  }
  if ( $secret != '' ) {
    file { "$secret_file":
      ensure  => present,
      mode    => 600,
      owner   => root,
      group   => root,
      content => "$real_varnish_secret\n",
      require => Package['varnish'],
      notify  => [
                   Service['varnish'],
                   Service['varnishlog'],
                   Service['varnishncsa'],
                 ],
    }
  }

  #############################################
  ## Configure the services                  ##
  #############################################
  $bool_start_service = $start_service ? {
    true    => 'yes',
    false   => 'no',
    default => 'yes',
  }
  $ensure_service_varnish = $start_service ? {
    true    => running,
    false   => stopped,
  }
  service { 'varnish':
    ensure => $ensure_service_varnish,
    require => Package['varnish'],
  }
  file { "/etc/default/varnish":
    ensure  => present,
    mode    => 644,
    owner   => root,
    group   => root,
    content => template('varnish4/varnish-default.erb'),
    notify  => Service['varnish'],
    require => Package['varnish'],
  }

  ## Varnish access log
  $bool_start_ncsa = $start_ncsa ? {
    true    => 'yes',
    false   => 'no',
    default => 'no',
  }
  $ensure_service_ncsa = $start_ncsa ? {
    true    => running,
    false   => stopped,
  }
  service { 'varnishncsa':
    ensure  => $ensure_service_ncsa,
    require => Service['varnish'],
  }
  file { "/etc/default/varnishncsa":
    ensure  => present,
    mode    => 644,
    owner   => root,
    group   => root,
    content => "VARNISHNCSA_ENABLED=$bool_start_ncsa\n",
    notify  => Service['varnishncsa'],
    require => Package['varnish'],
  }
  file { "/etc/init.d/varnishncsa":
    ensure  => present,
    mode    => 755,
    owner   => root,
    group   => root,
    content => template('varnish4/varnishncsa-init.erb'),
    notify  => Service['varnishncsa'],
    require => Package['varnish'],
  }

  ## Varnish debug log
  $bool_start_log = $start_log ? {
    true    => 'yes',
    false   => 'no',
    default => 'no',
  }
  $ensure_service_log = $start_log ? {
    true    => running,
    false   => stopped,
  }
  service { 'varnishlog':
    ensure  => $ensure_service_log,
    require => Service['varnish'],
  }
  file { "/etc/default/varnishlog":
    ensure  => present,
    mode    => 644,
    owner   => root,
    group   => root,
    content => "VARNISHLOG_ENABLED=$bool_start_log\nsleep 1\n",
    notify  => Service['varnishlog'],
    require => Package['varnish'],
  }

  #############################################
  ## Caching configuration                   ##
  #############################################
  if ($vcl_source != undef) {
    file { "$vcl_conf":
      ensure  => present,
      source  => $vcl_source,
      mode    => 644,
      owner   => root,
      group   => root,
      require => Package['varnish'],
      notify  => Service['varnish'],
    }
  }
}
