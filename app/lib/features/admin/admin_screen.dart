import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/sesion_service.dart';
import '../cart/carrito_service.dart';
import 'admin_service.dart';
import 'dialogo_confirmar.dart';
import 'restaurante_form_screen.dart';

// Estilo del panel: mismo lenguaje visual que el resto de la app
// (esquinas rectas, marcos finos y rótulos en mayúsculas).
const _borde = Color(0xFFD3E2DF);
const _menta = Color(0xFFE5F5F3);

TextStyle _rotulo({Color color = AppColors.hint, double size = 10}) {
  return AppTypography.body(color: color, weight: FontWeight.w700, size: size)
      .copyWith(letterSpacing: 1.5);
}

/// Columnas de la cuadrícula según el ancho disponible (5 en pantalla grande).
int _columnas(double ancho) {
  if (ancho >= 1500) return 5;
  if (ancho >= 1200) return 4;
  if (ancho >= 900) return 3;
  if (ancho >= 600) return 2;
  return 1;
}

/// Contenido a todo el ancho (se conserva el contenedor por orden del código).
class _Centrado extends StatelessWidget {
  final Widget child;

  const _Centrado({required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: child,
      ),
    );
  }
}

/// Encabezado de cada pestaña: rótulo, título y contador.
class _Encabezado extends StatelessWidget {
  final String rotulo;
  final String titulo;
  final String contador;
  final double lateral;

  const _Encabezado({
    required this.rotulo,
    required this.titulo,
    required this.contador,
    this.lateral = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(lateral, 20, lateral, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: _rotulo(size: 9.5)),
                const SizedBox(height: 4),
                Text(titulo, style: AppTypography.title(size: 26)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: _menta,
            child: Text(
              contador,
              style: AppTypography.body(weight: FontWeight.w600, size: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta blanca de esquinas rectas con borde fino.
class _Marco extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Marco({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borde),
      ),
      child: child,
    );
  }
}

/// Panel administrativo (Sprint 4, historias #16 y #17).
class AdminScreen extends StatelessWidget {
  final UsuarioAutenticado usuario;

  const AdminScreen({super.key, required this.usuario});

  void _cerrarSesion(BuildContext context) {
    SesionService.borrar();
    CarritoService.instance.vaciar();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            BarraSuperiorFE(
              titulo: 'Panel administrativo',
              // Es la pantalla de inicio del administrador: sin flecha de
              // regreso, con salida directa.
              conRegreso: Navigator.of(context).canPop(),
              acciones: [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => _cerrarSesion(context),
                  icon: const Icon(
                    Icons.logout,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: _borde)),
              ),
              child: TabBar(
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.primaryDark,
                unselectedLabelColor: AppColors.hint,
                labelStyle: AppTypography.body(
                  weight: FontWeight.w700,
                  size: 14,
                ),
                unselectedLabelStyle: AppTypography.body(
                  weight: FontWeight.w600,
                  size: 14,
                ),
                tabs: const [
                  Tab(text: 'Restaurantes'),
                  Tab(text: 'Usuarios y repartidores'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TabRestaurantes(usuario: usuario),
                  _TabUsuarios(usuario: usuario),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Pestaña 1: restaurantes (#16)
// ===========================================================================

class _TabRestaurantes extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const _TabRestaurantes({required this.usuario});

  @override
  State<_TabRestaurantes> createState() => _TabRestaurantesState();
}

class _TabRestaurantesState extends State<_TabRestaurantes>
    with AutomaticKeepAliveClientMixin {
  List<RestauranteAdmin> restaurantes = [];
  bool cargando = true;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultado = await AdminService.restaurantes(widget.usuario.token);
      if (!mounted) return;
      setState(() {
        restaurantes = resultado;
        cargando = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudieron cargar los restaurantes.';
        cargando = false;
      });
    }
  }

  Future<void> _abrirFormulario([RestauranteAdmin? restaurante]) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RestauranteFormScreen(
          usuario: widget.usuario,
          restaurante: restaurante,
        ),
      ),
    );
    if (cambio == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo_restaurante',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo restaurante'),
      ),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: restaurantes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    'Aún no hay restaurantes.',
                    style: AppTypography.subtitle(),
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, c) {
                final columnas = _columnas(c.maxWidth);
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Encabezado(
                        rotulo: 'ADMINISTRACIÓN',
                        titulo: 'Restaurantes',
                        contador: restaurantes.length == 1
                            ? '1 restaurante'
                            : '${restaurantes.length} restaurantes',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                      sliver: columnas == 1
                          ? SliverList.builder(
                              itemCount: restaurantes.length,
                              itemBuilder: (_, i) => _tarjeta(restaurantes[i]),
                            )
                          : SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columnas,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 236,
                              ),
                              itemCount: restaurantes.length,
                              itemBuilder: (_, i) =>
                                  _tarjetaCuadro(restaurantes[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Tarjeta para la cuadrícula (pantallas anchas).
  Widget _tarjetaCuadro(RestauranteAdmin r) {
    final detalle = [
      if ((r.categoria ?? '').isNotEmpty) r.categoria!,
      '${r.totalProductos} ${r.totalProductos == 1 ? 'producto' : 'productos'}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                color: _menta,
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.primaryDark,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        weight: FontWeight.w700,
                        size: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _rotulo(size: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if ((r.direccion ?? '').isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.direccion!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(size: 12.5),
                  ),
                ),
              ],
            ),
          if (r.latitud == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sin coordenadas: no aparece en la búsqueda por cercanía.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(color: AppColors.error, size: 11),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              onPressed: () => _abrirFormulario(r),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                side: const BorderSide(color: AppColors.primary),
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('Editar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(RestauranteAdmin r) {
    final detalle = [
      if ((r.categoria ?? '').isNotEmpty) r.categoria!,
      '${r.totalProductos} ${r.totalProductos == 1 ? 'producto' : 'productos'}',
    ].join(' · ');

    return _Marco(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            color: _menta,
            child: const Icon(
              Icons.storefront_outlined,
              color: AppColors.primaryDark,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.nombre,
                  style: AppTypography.body(weight: FontWeight.w700, size: 16),
                ),
                const SizedBox(height: 2),
                if ((r.direccion ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            r.direccion!,
                            style: AppTypography.body(size: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  detalle.toUpperCase(),
                  style: _rotulo(size: 10),
                ),
                if (r.latitud == null)
                  Text(
                    'Sin coordenadas: no aparece en la búsqueda por cercanía.',
                    style: AppTypography.body(color: AppColors.error, size: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _abrirFormulario(r),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Pestaña 2: usuarios y repartidores (#17)
// ===========================================================================

class _TabUsuarios extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const _TabUsuarios({required this.usuario});

  @override
  State<_TabUsuarios> createState() => _TabUsuariosState();
}

class _TabUsuariosState extends State<_TabUsuarios>
    with AutomaticKeepAliveClientMixin {
  static const _filtros = <(String?, String)>[
    (null, 'Todos'),
    ('cliente', 'Clientes'),
    ('repartidor', 'Repartidores'),
    ('administrador', 'Admins'),
  ];

  final TextEditingController _busqueda = TextEditingController();
  Timer? _espera;
  List<UsuarioAdmin> usuarios = [];
  bool cargando = true;
  String? error;
  String? _rol; // null = todos
  int _peticion = 0; // para ignorar respuestas viejas
  final Set<int> _ocupados = {}; // usuarios con un cambio en curso

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final numero = ++_peticion;
    try {
      final resultado = await AdminService.usuarios(
        widget.usuario.token,
        rol: _rol,
        busqueda: _busqueda.text,
      );
      if (!mounted || numero != _peticion) return;
      setState(() {
        usuarios = resultado;
        cargando = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || numero != _peticion) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted || numero != _peticion) return;
      setState(() {
        error = 'No se pudieron cargar los usuarios.';
        cargando = false;
      });
    }
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _cargar);
  }

  void _elegirFiltro(String? rol) {
    setState(() => _rol = rol);
    _cargar();
  }

  /// Aplica un cambio sobre un usuario y refresca su tarjeta.
  Future<void> _aplicar(
    UsuarioAdmin u,
    Future<UsuarioAdmin> Function() accion,
  ) async {
    setState(() => _ocupados.add(u.id));
    try {
      final nuevo = await accion();
      if (!mounted) return;
      setState(() {
        usuarios = [for (final x in usuarios) x.id == nuevo.id ? nuevo : x];
      });
      // Con un filtro por rol activo, el usuario pudo dejar de coincidir.
      if (_rol != null && nuevo.rol != _rol) _cargar();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupados.remove(u.id));
    }
  }

  Future<void> _cambiarActivo(UsuarioAdmin u, bool activo) async {
    if (!activo) {
      final ok = await confirmarAccion(
        context,
        titulo: 'Desactivar cuenta',
        mensaje:
            '${u.nombre} ya no podrá iniciar sesión hasta que la reactives.',
        textoConfirmar: 'Desactivar',
      );
      if (!ok || !mounted) return;
    }
    await _aplicar(
      u,
      () => AdminService.cambiarActivo(widget.usuario.token, u.id, activo),
    );
  }

  Future<void> _cambiarRol(UsuarioAdmin u, String rol) async {
    if (rol == 'administrador') {
      final ok = await confirmarAccion(
        context,
        titulo: 'Dar permisos de administrador',
        mensaje:
            '${u.nombre} podrá gestionar restaurantes, usuarios y repartidores.',
      );
      if (!ok || !mounted) return;
    }
    await _aplicar(
      u,
      () => AdminService.cambiarRol(widget.usuario.token, u.id, rol),
    );
  }

  (Color, IconData) _estiloRol(String rol) => switch (rol) {
        'administrador' => (AppColors.primaryDark, Icons.admin_panel_settings),
        'repartidor' => (AppColors.primary, Icons.delivery_dining),
        _ => (AppColors.hint, Icons.person),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _Centrado(
      child: Column(
        children: [
          _Encabezado(
            rotulo: 'ADMINISTRACIÓN',
            titulo: 'Usuarios y repartidores',
            contador: usuarios.length == 1
                ? '1 usuario'
                : '${usuarios.length} usuarios',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: TextField(
              controller: _busqueda,
              onChanged: _alEscribir,
              style: AppTypography.body(),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o correo',
                prefixIcon: Icon(Icons.search, color: AppColors.primaryDark),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: _borde),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: _borde),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (valor, texto) in _filtros) _filtro(valor, texto),
                ],
              ),
            ),
          ),
          Expanded(child: _lista()),
        ],
      ),
    );
  }

  Widget _filtro(String? valor, String texto) {
    final activo = _rol == valor;
    return InkWell(
      onTap: () => _elegirFiltro(valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: activo ? AppColors.primary : Colors.white,
          border: Border.all(color: activo ? AppColors.primary : _borde),
        ),
        child: Text(
          texto,
          style: AppTypography.body(
            color: activo ? Colors.white : AppColors.primaryDark,
            weight: FontWeight.w600,
            size: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _lista() {
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: usuarios.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 100),
                Center(
                  child: Text(
                    'No hay usuarios con ese filtro.',
                    style: AppTypography.subtitle(),
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, c) {
                final columnas = _columnas(c.maxWidth);
                if (columnas == 1) {
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: usuarios.length,
                    itemBuilder: (context, i) => _tarjeta(usuarios[i]),
                  );
                }
                return GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 176,
                  ),
                  itemCount: usuarios.length,
                  itemBuilder: (context, i) => _tarjetaCuadro(usuarios[i]),
                );
              },
            ),
    );
  }

  /// Tarjeta para la cuadrícula (pantallas anchas).
  Widget _tarjetaCuadro(UsuarioAdmin u) {
    final (color, icono) = _estiloRol(u.rol);
    final ocupado = _ocupados.contains(u.id);
    final etiqueta =
        u.activo ? nombreRol(u.rol) : '${nombreRol(u.rol)} · Desactivado';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                color: color,
                child: Icon(icono, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        weight: FontWeight.w700,
                        size: 15,
                      ),
                    ),
                    Text(
                      u.correo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTypography.body(color: AppColors.hint, size: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            etiqueta.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _rotulo(
              color: u.activo ? color : AppColors.error,
              size: 9.5,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Switch(
                value: u.activo,
                onChanged:
                    ocupado ? null : (valor) => _cambiarActivo(u, valor),
              ),
              Text(
                u.activo ? 'Activo' : 'Inactivo',
                style: AppTypography.body(size: 12.5),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Cambiar rol',
                enabled: !ocupado,
                icon: const Icon(Icons.more_vert),
                onSelected: (rol) => _cambiarRol(u, rol),
                itemBuilder: (_) => [
                  for (final rol in const [
                    'cliente',
                    'repartidor',
                    'administrador',
                  ])
                    PopupMenuItem<String>(
                      value: rol,
                      enabled: rol != u.rol,
                      child: Text('Hacer ${nombreRol(rol).toLowerCase()}'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(UsuarioAdmin u) {
    final (color, icono) = _estiloRol(u.rol);
    final ocupado = _ocupados.contains(u.id);
    final etiqueta =
        u.activo ? nombreRol(u.rol) : '${nombreRol(u.rol)} · Desactivado';

    return _Marco(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            color: color,
            child: Icon(icono, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.nombre,
                  style: AppTypography.body(weight: FontWeight.w700, size: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  u.correo,
                  style: AppTypography.body(color: AppColors.hint, size: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  etiqueta.toUpperCase(),
                  style: _rotulo(
                    color: u.activo ? color : AppColors.error,
                    size: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: u.activo,
            onChanged: ocupado ? null : (valor) => _cambiarActivo(u, valor),
          ),
          PopupMenuButton<String>(
            tooltip: 'Cambiar rol',
            enabled: !ocupado,
            icon: const Icon(Icons.more_vert),
            onSelected: (rol) => _cambiarRol(u, rol),
            itemBuilder: (_) => [
              for (final rol in const ['cliente', 'repartidor', 'administrador'])
                PopupMenuItem<String>(
                  value: rol,
                  enabled: rol != u.rol,
                  child: Text('Hacer ${nombreRol(rol).toLowerCase()}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}