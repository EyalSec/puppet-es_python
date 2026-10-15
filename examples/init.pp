# puppet apply --noop examples/init.pp
class { 'es_python':
  api_key    => Sensitive('es2_replace_me'),
  authorized => true,
  user       => 'app',
}
