/// Formato de dinero para las pantallas: 180 -> "$180.00".
String dinero(double valor) => '\$${valor.toStringAsFixed(2)}';
