# @summary
#
# Installs tailscale and adds to the network via tailscale up
#
# @param $auth_key 
#   the authorization key either onetime or multi-use
#
# @param $base_pkg_url
#   the base url of where to get the package
#
# @param $up_options
#   the options to use when running tailscale up for the first time
#
# @param $use_node_encrypt
#   use node encrypt when running tailscale up.  This requires a puppetserver and node encrypt
# @example
#   include tailscale
class tailscale (
  Variant[String, Sensitive[String]] $auth_key,
  Stdlib::HttpUrl $base_pkg_url,
  Boolean $manage_package = true,
  Boolean $manage_service = false,
  Boolean $manage_package_repository = true,
  Hash $up_options = {},
  Boolean $use_node_encrypt = false,
  String $service_provider = undef
) {
  if $manage_package_repository {
    case $facts['os']['family'] {
      'Debian': {
        apt::source { 'tailscale':
          comment  => 'Tailscale packages for ubuntu',
          location => $base_pkg_url,
          require  => Apt_key['tailscale'],
          before   => Package['tailscale'],
        }
        apt_key { 'tailscale':
          ensure => present,
          id     => '2596A99EAAB33821893C0A79458CA832957F5868',
          source => "${base_pkg_url}/focal.gpg",
        }
      }
      'RedHat': {
        yumrepo { 'tailscale-stable':
          ensure   => 'present',
          descr    => 'Tailscale stable',
          baseurl  => "${base_pkg_url}/${facts['os']['release']['major']}/\$basearch",
          gpgkey   => "${base_pkg_url}/${facts['os']['release']['major']}/repo.gpg",
          enabled  => '1',
          gpgcheck => '0',
          target   => '/etc/yum.repo.d/tailscale-stable.repo',
        }
      }
      default: {
        fail('OS not support for tailscale')
      }
    }
  }
  if $manage_package {
    package { 'tailscale':
      ensure  => present,
    }
  }
  if $manage_service {
    service { 'tailscaled':
      ensure   => running,
      enable   => true,
      provider => $service_provider,
      require  => [Package['tailscale']],
    }
  }

  $up_cli_options =  $up_options.map |$key, $value| {
    $equalsval = $value ? {
      String[1] => "=${value}",
      Boolean   => "=${bool2str($value)}",
      default   => '',
    }
    "--${key}${equalsval}"
  }.join(' ')

  if $use_node_encrypt {
    # uses node encrypt to unwrap the sensitive value then encrypts it
    # on the command line during execution the value is decrypted and never exposed to logs since the value
    # is temporary only exposed in a env variable
    $ts_command = "tailscale up --authkey=\$(puppet node decrypt --env SECRET) ${up_cli_options}".rstrip
    $env = ["SECRET=${node_encrypt($auth_key.unwrap)}"]
  } else {
    $ts_command = "tailscale up --authkey=\$SECRET ${up_cli_options}".rstrip
    $env = ["SECRET=${auth_key.unwrap}"]
  }
  exec { 'run tailscale up':
    command     => $ts_command,
    provider    => shell,
    environment => $env,
    unless      => 'test $(tailscale status | wc -l) -gt 1',
    require     => Service['tailscaled'],
  }
}
