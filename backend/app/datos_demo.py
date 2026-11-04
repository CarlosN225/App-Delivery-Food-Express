"""
Datos de demostración de Food Express.

Los restaurantes son negocios locales reales de Nicolás Romero, Edo. Méx.
(sin cadenas): el nombre, la calle y las coordenadas se tomaron de Google
Maps. En el repositorio solo se guarda la calle (sin número) y la colonia
cuando se conoce.

Los MENÚS Y PRECIOS son de prueba (inventados). No representan la carta
real de cada negocio.

Categorías de la app: Pizza, Tacos, Hamburguesas, Sushi, Postres, Café, Otros.
Cada producto es una tupla: (nombre, descripción, precio, categoría del menú).
"""

RESTAURANTES = [
    # ---------------- TACOS ----------------
    {
        "nombre": "Taquería El Moreno",
        "direccion": "Emiliano Zapata, El Tráfico, Nicolás Romero",
        "categoria": "Tacos",
        "latitud": "19.6187191",
        "longitud": "-99.3267704",
        "productos": [
            ("Orden de tacos al pastor", "5 tacos al pastor con piña, cebolla y cilantro.", "75.00", "Tacos"),
            ("Orden de tacos de bistec", "5 tacos de bistec con cebolla y cilantro.", "85.00", "Tacos"),
            ("Gringa de pastor", "Tortilla de harina con pastor y queso fundido.", "55.00", "Tacos"),
            ("Quesadilla con carne", "Quesadilla de maíz con queso y carne a elegir.", "50.00", "Antojitos"),
            ("Agua fresca 500 ml", "Horchata o jamaica.", "25.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Taquería Lucky",
        "direccion": "Av. Hidalgo, Nicolás Romero",
        "categoria": "Tacos",
        "latitud": "19.6187864",
        "longitud": "-99.3085897",
        "productos": [
            ("Tacos de suadero (5)", "Suadero dorado con cebolla y cilantro.", "80.00", "Tacos"),
            ("Tacos campechanos (5)", "Mezcla de bistec y chorizo.", "90.00", "Tacos"),
            ("Alambre", "Bistec, tocino, pimiento y queso con tortillas.", "120.00", "Especialidades"),
            ("Costra de pastor", "Tortilla dorada con queso y pastor.", "65.00", "Especialidades"),
            ("Refresco 600 ml", "Coca-Cola, Sprite o Fanta.", "28.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Taquería Los Grillos",
        "direccion": "C. Rodolfo Gaona, Nicolás Romero",
        "categoria": "Tacos",
        "latitud": "19.6142874",
        "longitud": "-99.2919070",
        "productos": [
            ("Tacos al pastor (5)", "Pastor del trompo con piña.", "75.00", "Tacos"),
            ("Tacos de carnitas (5)", "Carnitas de cerdo con salsa verde.", "85.00", "Tacos"),
            ("Volcán de bistec", "Tortilla tostada con queso y bistec.", "45.00", "Antojitos"),
            ("Tacos de longaniza (5)", "Longaniza dorada con cebolla.", "80.00", "Tacos"),
            ("Agua de horchata 1 L", "Agua fresca de horchata.", "40.00", "Bebidas"),
        ],
    },
    {
        "nombre": "La Parrilla de Betos",
        "direccion": "Nicolás Romero",
        "categoria": "Tacos",
        "latitud": "19.6041144",
        "longitud": "-99.3022252",
        "productos": [
            ("Tacos de arrachera (4)", "Arrachera a la parrilla con cebolla cambray.", "130.00", "Parrilla"),
            ("Tacos de costilla (4)", "Costilla de res asada.", "120.00", "Parrilla"),
            ("Queso fundido con chorizo", "Queso fundido con chorizo y tortillas.", "95.00", "Entradas"),
            ("Cebollitas asadas", "Cebollitas cambray con limón.", "35.00", "Entradas"),
            ("Refresco 600 ml", "Coca-Cola, Sprite o Fanta.", "28.00", "Bebidas"),
        ],
    },

    # ---------------- HAMBURGUESAS ----------------
    {
        "nombre": "Hamburguesas Beto",
        "direccion": "C. Mariano Escobedo, Zaragoza, Nicolás Romero",
        "categoria": "Hamburguesas",
        "latitud": "19.6318072",
        "longitud": "-99.3272853",
        "productos": [
            ("Hamburguesa clásica", "Carne de res, queso, lechuga, jitomate y cebolla.", "85.00", "Hamburguesas"),
            ("Hamburguesa doble queso", "Doble carne con doble queso amarillo.", "110.00", "Hamburguesas"),
            ("Hamburguesa BBQ bacon", "Carne, tocino, queso y salsa BBQ.", "120.00", "Hamburguesas"),
            ("Papas a la francesa", "Porción mediana con sal.", "45.00", "Complementos"),
            ("Refresco 600 ml", "Coca-Cola, Sprite o Fanta.", "28.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Hamburguesas Suspiro",
        "direccion": "Av. 16 de Septiembre, Nicolás Romero",
        "categoria": "Hamburguesas",
        "latitud": "19.6238339",
        "longitud": "-99.3170973",
        "productos": [
            ("Hamburguesa sencilla", "Carne, jamón, queso, jitomate y lechuga.", "70.00", "Hamburguesas"),
            ("Hamburguesa especial", "Carne, piña, tocino, jamón y queso.", "105.00", "Hamburguesas"),
            ("Hot dog jumbo", "Salchicha jumbo con tocino y aderezos.", "55.00", "Hot dogs"),
            ("Aros de cebolla", "Porción de aros empanizados.", "50.00", "Complementos"),
            ("Malteada de vainilla", "Malteada de 400 ml.", "55.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Hermanos Burger",
        "direccion": "Av. Hidalgo, Nicolás Romero",
        "categoria": "Hamburguesas",
        "latitud": "19.6189163",
        "longitud": "-99.3092478",
        "productos": [
            ("Burger Hermanos", "Carne de res, queso cheddar, tocino y cebolla caramelizada.", "125.00", "Hamburguesas"),
            ("Burger pollo crujiente", "Pechuga empanizada con lechuga y chipotle.", "110.00", "Hamburguesas"),
            ("Boneless (10 pzas)", "Boneless BBQ o búfalo.", "120.00", "Complementos"),
            ("Papas gajo", "Papas gajo sazonadas.", "55.00", "Complementos"),
            ("Limonada 500 ml", "Limonada natural.", "35.00", "Bebidas"),
        ],
    },

    # ---------------- PIZZA ----------------
    {
        "nombre": "Hermano's Pizza",
        "direccion": "Av. 16 de Septiembre, Nicolás Romero",
        "categoria": "Pizza",
        "latitud": "19.6268083",
        "longitud": "-99.3194297",
        "productos": [
            ("Pizza pepperoni mediana", "Salsa de tomate, queso mozzarella y pepperoni.", "159.00", "Pizzas"),
            ("Pizza hawaiana mediana", "Jamón, piña y queso mozzarella.", "159.00", "Pizzas"),
            ("Pizza mexicana mediana", "Chorizo, jalapeño, cebolla y queso.", "169.00", "Pizzas"),
            ("Pan de ajo", "Pan con mantequilla de ajo y queso gratinado.", "69.00", "Complementos"),
            ("Refresco 2 L", "Coca-Cola.", "42.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Angelo's Pizza",
        "direccion": "Cda. Rancho el Edén, Nicolás Romero",
        "categoria": "Pizza",
        "latitud": "19.6082011",
        "longitud": "-99.3314847",
        "productos": [
            ("Pizza 4 quesos mediana", "Mozzarella, manchego, parmesano y queso crema.", "189.00", "Pizzas"),
            ("Pizza margarita mediana", "Jitomate, albahaca y mozzarella.", "149.00", "Pizzas"),
            ("Pizza carnes frías grande", "Jamón, salami, pepperoni y tocino.", "239.00", "Pizzas"),
            ("Alitas BBQ (8 pzas)", "Alitas bañadas en salsa BBQ.", "115.00", "Complementos"),
            ("Refresco 2 L", "Coca-Cola.", "42.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Pizzas Don George",
        "direccion": "Av. Hidalgo, Nicolás Romero",
        "categoria": "Pizza",
        "latitud": "19.6201382",
        "longitud": "-99.3127541",
        "productos": [
            ("Pizza de pepperoni individual", "Pizza individual de 20 cm.", "89.00", "Pizzas"),
            ("Pizza de champiñón mediana", "Champiñón, queso y orégano.", "155.00", "Pizzas"),
            ("Pizza vegetariana mediana", "Pimiento, cebolla, champiñón y aceituna.", "165.00", "Pizzas"),
            ("Dedos de queso (6 pzas)", "Con salsa marinara.", "75.00", "Complementos"),
            ("Agua de jamaica 1 L", "Agua fresca.", "38.00", "Bebidas"),
        ],
    },

    # ---------------- CAFÉ ----------------
    {
        "nombre": "Arte Latte",
        "direccion": "Av. La Colmena, Col. La Colmena, Nicolás Romero",
        "categoria": "Café",
        "latitud": "19.6009551",
        "longitud": "-99.2892994",
        "productos": [
            ("Café americano", "Café de grano, 12 oz.", "40.00", "Café"),
            ("Latte vainilla", "Espresso con leche vaporizada y vainilla.", "58.00", "Café"),
            ("Frappé de moka", "Frappé de chocolate y café.", "70.00", "Frappés"),
            ("Croissant de jamón y queso", "Croissant horneado al día.", "55.00", "Alimentos"),
            ("Rebanada de pastel de zanahoria", "Pastel con betún de queso crema.", "62.00", "Postres"),
        ],
    },
    {
        "nombre": "Café Moustach",
        "direccion": "Av. 16 de Septiembre, Nicolás Romero",
        "categoria": "Café",
        "latitud": "19.6247590",
        "longitud": "-99.3177994",
        "productos": [
            ("Cappuccino", "Espresso con espuma de leche, 12 oz.", "52.00", "Café"),
            ("Café de olla", "Café con canela y piloncillo.", "38.00", "Café"),
            ("Chai latte", "Té chai especiado con leche.", "60.00", "Bebidas"),
            ("Sándwich de pollo", "Pollo, queso, lechuga y jitomate.", "78.00", "Alimentos"),
            ("Galleta de chispas", "Galleta grande artesanal.", "30.00", "Postres"),
        ],
    },

    # ---------------- POSTRES ----------------
    {
        "nombre": "Pastelería El Maná",
        "direccion": "C. Benito Juárez, Nicolás Romero",
        "categoria": "Postres",
        "latitud": "19.6253818",
        "longitud": "-99.3189507",
        "productos": [
            ("Rebanada de pastel de chocolate", "Pastel húmedo con betún de chocolate.", "55.00", "Pasteles"),
            ("Rebanada de pastel tres leches", "Tres leches con crema chantilly.", "58.00", "Pasteles"),
            ("Cheesecake de fresa", "Rebanada con mermelada de fresa.", "65.00", "Pasteles"),
            ("Gelatina de rompope", "Vaso de gelatina cremosa.", "30.00", "Postres"),
            ("Caja de 6 donas", "Donas glaseadas surtidas.", "90.00", "Postres"),
        ],
    },
    {
        "nombre": "Pasteles Ammmbigú",
        "direccion": "C. Río Bravo, Nicolás Romero",
        "categoria": "Postres",
        "latitud": "19.6149304",
        "longitud": "-99.3115761",
        "productos": [
            ("Pastel chico de vainilla", "Pastel para 8 personas.", "280.00", "Pasteles"),
            ("Cupcakes (4 pzas)", "Cupcakes decorados de vainilla o chocolate.", "100.00", "Postres"),
            ("Brownie con nuez", "Brownie individual.", "35.00", "Postres"),
            ("Flan napolitano", "Porción individual.", "40.00", "Postres"),
            ("Rol de canela", "Rol con betún de queso crema.", "45.00", "Postres"),
        ],
    },

    # ---------------- SUSHI ----------------
    {
        "nombre": "Máster Roll Sushi",
        "direccion": "C. De las Flores, Nicolás Romero",
        "categoria": "Sushi",
        "latitud": "19.6271737",
        "longitud": "-99.2996555",
        "productos": [
            ("Roll California", "Surimi, pepino y aguacate, 8 piezas.", "95.00", "Rollos"),
            ("Roll Philadelphia", "Queso crema, salmón y pepino, 8 piezas.", "120.00", "Rollos"),
            ("Roll empanizado especial", "Roll empanizado con camarón y queso crema.", "135.00", "Rollos"),
            ("Gyozas (5 pzas)", "Gyozas de cerdo a la plancha.", "75.00", "Entradas"),
            ("Té helado 500 ml", "Té verde o durazno.", "32.00", "Bebidas"),
        ],
    },

    # ---------------- OTROS ----------------
    {
        "nombre": "La Crudería",
        "direccion": "Av. Guadalupe Victoria, Rincón de San José, Nicolás Romero",
        "categoria": "Otros",
        "latitud": "19.6518758",
        "longitud": "-99.3788496",
        "productos": [
            ("Tostada de atún", "Tostada con atún fresco, aguacate y chipotle.", "95.00", "Entradas"),
            ("Aguachile verde", "Camarón en salsa verde con pepino y cebolla morada.", "180.00", "Mariscos"),
            ("Ceviche de camarón", "Camarón curtido en limón con jitomate y cilantro.", "170.00", "Mariscos"),
            ("Campechana de mariscos", "Camarón, pulpo y callo en salsa.", "210.00", "Mariscos"),
            ("Agua de jamaica 500 ml", "Agua fresca.", "30.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Samba Da Brasa Churrasca",
        "direccion": "C. Francisco Villa, Col. Morelos, Nicolás Romero",
        "categoria": "Otros",
        "latitud": "19.6389679",
        "longitud": "-99.3439377",
        "productos": [
            ("Picanha a la parrilla", "Corte de picanha con arroz y farofa.", "320.00", "Parrilla"),
            ("Costilla BBQ", "Costilla de cerdo con salsa BBQ y papas.", "290.00", "Parrilla"),
            ("Pollo al carbón", "Medio pollo al carbón con ensalada.", "210.00", "Parrilla"),
            ("Pão de queijo (6 pzas)", "Pan brasileño de queso.", "70.00", "Entradas"),
            ("Limonada con menta 500 ml", "Limonada natural.", "40.00", "Bebidas"),
        ],
    },
    {
        "nombre": "Restaurante El Sazón",
        "direccion": "Av. Hidalgo, Nicolás Romero",
        "categoria": "Otros",
        "latitud": "19.6187716",
        "longitud": "-99.3081034",
        "productos": [
            ("Desayuno mexicano", "Huevos al gusto, frijoles, café y pan.", "95.00", "Desayunos"),
            ("Chilaquiles con pollo", "Salsa verde o roja con crema y queso.", "90.00", "Desayunos"),
            ("Caldo de camarón", "Caldo con camarón, verduras y arroz.", "160.00", "Mariscos"),
            ("Filete empanizado", "Filete de pescado con arroz y ensalada.", "150.00", "Mariscos"),
            ("Agua de jamaica 500 ml", "Agua fresca.", "30.00", "Bebidas"),
        ],
    },
]

# Restaurantes ficticios de la versión anterior de los datos de prueba.
# Se eliminan al cargar los reales, salvo que ya tengan pedidos.
RESTAURANTES_ANTERIORES = [
    "Pizza Express",
    "Hamburguesas El Buen Sabor",
    "Tacos Don Juan",
    "Sushi House",
]
