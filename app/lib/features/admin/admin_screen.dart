import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import 'admin_service.dart';
import 'dialogo_confirmar.dart';
import 'restaurante_form_screen.dart';

/// Panel administrativo (Sprint 4, historias #16 y #17).
class AdminScreen extends StatelessWidget {
  final UsuarioAutenticado usuario;

  const AdminScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: buildAppBar(
          'Panel administrativo',
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Restaurantes'),
              Tab(text: 'Usuarios y repartidores'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TabRestaurantes(usuario: usuario),
            _TabUsuarios(usuario: usuario),
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
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: restaurantes.length,
              itemBuilder: (context, i) => _tarjeta(restaurantes[i]),
            ),
    );
  }

  Widget _tarjeta(RestauranteAdmin r) {
    final detalle = [
      if ((r.categoria ?? '').isNotEmpty) r.categoria!,
      '${r.totalProductos} ${r.totalProductos == 1 ? 'producto' : 'productos'}',
    ].join(' · ');

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F6F2),
              borderRadius: BorderRadius.circular(12),
            ),
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
                Text(
                  detalle,
                  style: AppTypography.body(color: AppColors.hint, size: 12),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: TextField(
            controller: _busqueda,
            onChanged: _alEscribir,
            style: AppTypography.body(),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o correo',
              hintStyle: AppTypography.body(color: AppColors.hint),
              prefixIcon: const Icon(Icons.search, color: AppColors.primaryDark),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                for (final (valor, texto) in _filtros)
                  ChoiceChip(
                    label: Text(texto),
                    selected: _rol == valor,
                    selectedColor: AppColors.primary,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _rol == valor ? Colors.white : AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => _elegirFiltro(valor),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: _lista()),
      ],
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
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: usuarios.length,
              itemBuilder: (context, i) => _tarjeta(usuarios[i]),
            ),
    );
  }

  Widget _tarjeta(UsuarioAdmin u) {
    final (color, icono) = _estiloRol(u.rol);
    final ocupado = _ocupados.contains(u.id);
    final etiqueta =
        u.activo ? nombreRol(u.rol) : '${nombreRol(u.rol)} · Desactivado';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
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
                  etiqueta,
                  style: AppTypography.body(
                    color: u.activo ? color : AppColors.error,
                    size: 12,
                    weight: FontWeight.w600,
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