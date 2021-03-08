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
class tailscale(
  Sensitive[String] $auth_key,
  Stdlib::HttpUrl $base_pkg_url,
  Hash $up_options = {},
  Boolean $use_node_encrypt = false
) {
  case $::facts[osfamily] {
    'Debian': {
      apt::source { 'tailscale':
        comment  => 'Tailscale packages for ubuntu',
        location => $base_pkg_url,
        require  => Apt_key['tailscale'],
        before   => Package['tailscale']

      }
      apt_key{'tailscale':
        ensure => present,
        id     => '2596A99EAAB33821893C0A79458CA832957F5868',
        source => "${base_pkg_url}/focal.gpg"
      }
    }
    'RedHat': {
      yumrepo { 'tailscale-stable':
        ensure   => 'present',
        descr    => 'Tailscale stable',
        baseurl  => "${base_pkg_url}/${facts[operatingsystemmajrelease]}/\$basearch",
        gpgkey   => "${base_pkg_url}/${facts[operatingsystemmajrelease]}/repo.gpg",
        enabled  => '1',
        gpgcheck => '0',
        target   => '/etc/yum.repo.d/tailscale-stable.repo',
      }
    }
    default: {
      fail('OS not support for tailscale')
    }
  }
  package{'tailscale':
    ensure  => present,
  }
  service{'tailscaled':
    ensure  => running,
    enable  => true,
    require => [Package['tailscale']]
  }

  $up_cli_options =  $up_options.map |$key, $value| { "-${key} ${value}"}.join(' ')

  if $use_node_encrypt {
    # uses node encrypt to unwrap the sensitive value then encrypts it
    # on the command line during execution the value is decrypted and never exposed to logs since the value
    # is temporary only exposed in a env variable
    exec{'run tailscale up':
      command     => "tailscale up -authkey \$(puppet node decrypt --env SECRET) ${up_cli_options}",
      provider    => shell,
      environment => ["SECRET=${node_encrypt($auth_key)}"],
      unless      => 'test $(tailscale status | wc -l) -gt 1',
      require     => Service['tailscaled']
    }
  } else {
    exec{'run tailscale up':
      command     => "tailscale up -authkey \$SECRET ${up_cli_options}",
      provider    => shell,
      environment => ["SECRET=${auth_key.unwrap}"],
      unless      => 'test $(tailscale status | wc -l) -gt 1',
      require     => Service['tailscaled']
    }
  }
}