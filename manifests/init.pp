# @summary Installs es-python, the EyalSec Python runtime, for one user.
#
# Installs es-python the way the install command on the EyalSec Machines page
# does. With an API key, the node is found by machine name on your account and
# added on the first run. Once es-python is installed for the user, later runs
# change nothing.
#
# The credential reaches the installer through its environment and is never
# placed on a command line or in the run's log.
#
# @example One key for the fleet, from Hiera (encrypt it with hiera-eyaml)
#   class { 'es_python':
#     api_key    => Sensitive(lookup('es_python::api_key')),
#     authorized => true,
#     user       => 'app',
#   }
#
# @param api_key
#   A full-access EyalSec API key (Settings > API access). One key serves every
#   node. Set this or install_secret.
# @param install_secret
#   A one-time install secret for one machine. It works once and expires 10
#   minutes after it was issued.
# @param authorized
#   Required with an API key: your confirmation that you own this node or are
#   authorized to monitor it, the same statement as the tick box on the
#   Machines page.
# @param user
#   The user es-python is installed for. es-python installs into this user's
#   home and runs as this user.
# @param machine_name
#   The machine name this node reports under. Each node needs its own.
# @param python_version
#   3.9 to 3.14. Leave undef to match the node's own python3.
# @param url
#   Your EyalSec address.
# @param manage_dependencies
#   Install curl and CA certificates when they are missing.
# @param helper_path
#   Where the install helper is placed.
class es_python (
  Optional[Sensitive[String[1]]] $api_key = undef,
  Optional[Sensitive[String[1]]] $install_secret = undef,
  Boolean $authorized = false,
  String[1] $user = 'root',
  String[1, 128] $machine_name = $trusted['certname'],
  Optional[Enum['3.9', '3.10', '3.11', '3.12', '3.13', '3.14']] $python_version = undef,
  Pattern[/\Ahttps:\/\//] $url = 'https://eyalsec.com',
  Boolean $manage_dependencies = true,
  Pattern[/\A\/[^\s]+\z/] $helper_path = '/usr/local/libexec/eyalsec/es-python-fleet-install.sh',
) {
  if $api_key == undef and $install_secret == undef {
    fail('es_python: set api_key or install_secret')
  }
  if $api_key != undef and !$authorized {
    fail('es_python: set authorized => true to confirm you own this node or are authorized to monitor it')
  }

  if $manage_dependencies {
    $packages = $facts['os']['family'] ? {
      'Debian' => ['curl', 'ca-certificates'],
      default  => ['ca-certificates'],
    }
    $packages.each |String $p| {
      if !defined(Package[$p]) {
        package { $p:
          ensure => installed,
          before => Exec['es_python install'],
        }
      }
    }
  }

  $helper_dir = regsubst($helper_path, '/[^/]+\z', '')
  exec { 'es_python helper directory':
    command => "mkdir -p '${helper_dir}'",
    creates => $helper_dir,
    path    => ['/usr/bin', '/bin'],
  }
  -> file { $helper_path:
    ensure => file,
    owner  => 'root',
    group  => '0',
    mode   => '0755',
    source => 'puppet:///modules/es_python/es-python-fleet-install.sh',
  }

  $version_env = $python_version ? {
    undef   => [],
    default => ["EYALSEC_PYTHON_VERSION=${python_version}"],
  }
  $credential_env = $api_key ? {
    undef   => ["EYALSEC_INSTALL_SECRET=${install_secret.unwrap}"],
    default => ["EYALSEC_API_KEY=${api_key.unwrap}"],
  }
  $settings_env = [
    "EYALSEC_URL=${url}",
    "EYALSEC_MACHINE=${machine_name}",
    "EYALSEC_AUTHORIZED=${authorized}",
  ] + $version_env

  exec { 'es_python install':
    command     => "/bin/sh '${helper_path}'",
    unless      => "/bin/sh '${helper_path}' --check",
    user        => $user,
    cwd         => '/',
    environment => $settings_env + $credential_env,
    path        => ['/usr/local/sbin', '/usr/local/bin', '/usr/sbin', '/usr/bin', '/sbin', '/bin'],
    timeout     => 1800,
    logoutput   => true,
    require     => File[$helper_path],
  }
}
