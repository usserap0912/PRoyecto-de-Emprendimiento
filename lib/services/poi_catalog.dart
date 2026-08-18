/// Catálogo central de lugares auditados de Collique.
///
/// Solo [productionPois] puede ser consumido por la interfaz de producción.
/// Las demás colecciones conservan evidencia para revisiones posteriores.
class PoiCatalog {
  const PoiCatalog._();

  static const String verifiedStatus = 'VERIFIED';
  static const String partiallyVerifiedStatus = 'PARTIALLY_VERIFIED';
  static const String unverifiedStatus = 'UNVERIFIED';
  static const String rejectedStatus = 'REJECTED';
  static const String verificationDate = '2026-08-17';

  static Map<String, dynamic> _verified({
    required String name,
    required double lat,
    required double lng,
    required String type,
    required String category,
    required String categoryLabel,
    required String source,
    required String sourceId,
    required String coordinateRole,
    int? zoneNumber,
    String confidence = 'high',
    String scopeClass = 'inside_collique',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'name': name,
      'lat': lat,
      'lng': lng,
      'type': type,
      'category': category,
      'categoryLabel': categoryLabel,
      'zoneNumber': zoneNumber,
      'verified': true,
      'verificationStatus': verifiedStatus,
      'confidence': confidence,
      'productionVisible': true,
      'scopeClass': scopeClass,
      'coordinateRole': coordinateRole,
      'source': source,
      'sourceId': sourceId,
      'verifiedAt': verificationDate,
      ...metadata,
    };
  }

  static Map<String, dynamic> _audit({
    required String name,
    required String type,
    required String category,
    required String verificationStatus,
    required String verificationReason,
    double? lat,
    double? lng,
    int? zoneNumber,
    String? source,
  }) {
    return <String, dynamic>{
      'name': name,
      'lat': lat,
      'lng': lng,
      'type': type,
      'category': category,
      'zoneNumber': zoneNumber,
      'verified': false,
      'verificationStatus': verificationStatus,
      'productionVisible': false,
      'source': source ?? 'Auditoría geográfica de Collique',
      'verificationReason': verificationReason,
    };
  }

  static final List<Map<String, dynamic>>
  productionPois = List<Map<String, dynamic>>.unmodifiable(<
    Map<String, dynamic>
  >[
    _verified(
      name: 'Hospital Nacional Sergio E. Bernales',
      lat: -11.9141196,
      lng: -77.0376892,
      type: 'hospital',
      category: 'health',
      categoryLabel: 'Salud',
      source: 'Hospital Nacional Sergio E. Bernales / OpenStreetMap',
      sourceId: 'way/110061951',
      coordinateRole: 'building_footprint_center',
      scopeClass: 'entrance_reference',
      metadata: <String, dynamic>{
        'address': 'Av. Túpac Amaru N.º 8000, P.J. Collique, Comas, Lima',
        'officialSourceId':
            'https://www.gob.pe/institucion/hnseb/contacto-y-numeros-de-emergencias',
      },
    ),
    _verified(
      name: 'Mercado Central I de Collique',
      lat: -11.9153695,
      lng: -77.0330272,
      type: 'mercado',
      category: 'markets',
      categoryLabel: 'Mercados',
      source: 'Registro oficial de mercados / OpenStreetMap',
      sourceId: 'way/802704644',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 1,
      metadata: <String, dynamic>{'address': 'Av. Revolución 1040, I Zona'},
    ),
    _verified(
      name: 'I.E. 2086 Perú Holanda',
      lat: -11.9165007,
      lng: -77.0350951,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'PRONIED / UGEL 04 / OpenStreetMap',
      sourceId: 'way/122215524',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 1,
      metadata: <String, dynamic>{'address': 'Jr. Túpac Amaru 200, I Zona'},
    ),
    _verified(
      name: 'I.E. Andrés Avelino Cáceres Dorregaray',
      lat: -11.9166508,
      lng: -77.0337318,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'UGEL 04 / OpenStreetMap',
      sourceId: 'way/601205612',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 1,
      metadata: <String, dynamic>{
        'address': 'Jr. Ciro Alegría s/n, Mz. Z, I Zona',
      },
    ),
    _verified(
      name: 'Full Oils Petro S.A.C.',
      lat: -11.9149,
      lng: -77.0346,
      type: 'grifo',
      category: 'fuel',
      categoryLabel: 'Grifos / EESS',
      source: 'OSINERGMIN',
      sourceId: 'FeatureServer/35/OBJECTID/10237',
      coordinateRole: 'official_gis_point',
      zoneNumber: 1,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución 783, Primera Zona Collique',
        'registryId': '7255-050-050522',
        'ruc': '20517849368',
      },
    ),
    _verified(
      name: 'I.E. 2038 Inca Garcilaso de la Vega',
      lat: -11.9179833,
      lng: -77.0288616,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'PRONIED / UGEL 04 / OpenStreetMap',
      sourceId: 'way/605465248',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 2,
      metadata: <String, dynamic>{'address': 'Jr. Santa Cruz 222, II Zona'},
    ),
    _verified(
      name: 'Centro de Salud Collique III Zona',
      lat: -11.9150061,
      lng: -77.0261919,
      type: 'centro_salud',
      category: 'health',
      categoryLabel: 'Salud',
      source: 'DIRIS Lima Norte / MINSA / OpenStreetMap',
      sourceId: 'way/835883275',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 3,
      metadata: <String, dynamic>{
        'address': 'Av. Santa Rosa s/n, III Zona',
        'officialSourceId':
            'https://www.gob.pe/institucion/dirislimanorte/noticias/1417035',
      },
    ),
    _verified(
      name: 'Museo de los Colli',
      lat: -11.9113963,
      lng: -77.0261052,
      type: 'museo',
      category: 'culture',
      categoryLabel: 'Cultura',
      source: 'Ministerio de Cultura / OpenStreetMap',
      sourceId: 'node/1932068160',
      coordinateRole: 'mapped_poi_point',
      zoneNumber: 3,
      metadata: <String, dynamic>{
        'address': 'Pasaje Libertad, lote 5, Mz. LL, III Zona',
        'addressVariant': 'Chasquis 253, Comas, Lima',
      },
    ),
    _verified(
      name: 'I.E. 2007 San Martín de Porres',
      lat: -11.914294,
      lng: -77.027894,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'UGEL 04 / OpenStreetMap',
      sourceId: 'way/436455874',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 3,
      metadata: <String, dynamic>{'address': 'Av. Revolución 1500, III Zona'},
    ),
    _verified(
      name: 'Corporación Megu S.A.C.',
      lat: -11.9130,
      lng: -77.0247,
      type: 'grifo',
      category: 'fuel',
      categoryLabel: 'Grifos / EESS',
      source: 'OSINERGMIN / OpenStreetMap',
      sourceId: 'FeatureServer/35/OBJECTID/11144',
      coordinateRole: 'official_gis_point',
      zoneNumber: 3,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución 1825, esquina Jr. Ica, III Zona',
        'registryId': '9203-056-030726',
        'ruc': '20517877574',
        'nameAliases': <String>['Grifo PECSA Collique'],
        'aliasStatus': 'cartographic_historical_not_current_operator',
        'cartographicSourceId': 'way/874334144',
      },
    ),
    _verified(
      name: 'Comisaría PNP Collique',
      lat: -11.9130804,
      lng: -77.0161997,
      type: 'comisaria',
      category: 'security',
      categoryLabel: 'Seguridad / PNP',
      source: 'Policía Nacional del Perú / OpenStreetMap',
      sourceId: 'way/318952708',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 4,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución 2591, IV Zona',
        'officialSourceId':
            'https://www.gob.pe/institucion/pnp/informes-publicaciones/7063170',
        'emergency_phone': '105',
      },
    ),
    _verified(
      name: 'Mercado 12 de Febrero',
      lat: -11.9115661,
      lng: -77.0219647,
      type: 'mercado',
      category: 'markets',
      categoryLabel: 'Mercados',
      source: 'Registro oficial de mercados / OpenStreetMap',
      sourceId: 'way/802703479',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 4,
      metadata: <String, dynamic>{
        'address':
            'Jr. Micaela Bastidas s/n, referencia Av. Revolución / Prol. Ramón Castilla',
      },
    ),
    _verified(
      name: 'CEDIF Collique',
      lat: -11.912618,
      lng: -77.0164851,
      type: 'equipamiento_social',
      category: 'social_equipment',
      categoryLabel: 'Equipamiento social',
      source: 'INABIF / OpenStreetMap',
      sourceId: 'way/789673262',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 4,
      confidence: 'medium_high',
      metadata: <String, dynamic>{'address': 'Jr. Felipe Pinglo s/n, IV Zona'},
    ),
    _verified(
      name: 'I.E. 2060 Virgen de Guadalupe',
      lat: -11.9107762,
      lng: -77.017115,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'ONPE / UGEL 04 / OpenStreetMap',
      sourceId: 'way/122242291',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 4,
      metadata: <String, dynamic>{
        'address': 'Jr. Micaela Bastidas 948, IV Zona',
      },
    ),
    _verified(
      name: 'Mercado CV Zona de Collique',
      lat: -11.9121487,
      lng: -77.0076125,
      type: 'mercado',
      category: 'markets',
      categoryLabel: 'Mercados',
      source: 'Registro oficial de mercados / OpenStreetMap',
      sourceId: 'way/802702667',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 5,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución 3175, V Zona',
        'nameAliases': <String>['Mercado V Zona Collique'],
      },
    ),
    _verified(
      name: 'Comisaría PNP de Familia Collique',
      lat: -11.9129766,
      lng: -77.0103792,
      type: 'comisaria',
      category: 'security',
      categoryLabel: 'Seguridad / PNP',
      source: 'MIMP / Policía Nacional del Perú / OpenStreetMap',
      sourceId: 'way/318949134',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 5,
      metadata: <String, dynamic>{
        'address': 'Av. Francisco de Zela s/n, V Zona',
        'addressVariant': 'Av. Revolución, cuadra 26',
        'emergency_phone': '105',
      },
    ),
    _verified(
      name: 'Centro de Salud Gustavo Lanatta Luján',
      lat: -11.9149135,
      lng: -77.0110434,
      type: 'centro_salud',
      category: 'health',
      categoryLabel: 'Salud',
      source: 'MINSA / DIGESA / OpenStreetMap',
      sourceId: 'way/819637390',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 5,
      metadata: <String, dynamic>{'address': 'Jr. Arequipa s/n, V Zona'},
    ),
    _verified(
      name: 'I.E. Fe y Alegría 13',
      lat: -11.9121894,
      lng: -77.009762,
      type: 'colegio',
      category: 'education',
      categoryLabel: 'Educación',
      source: 'UGEL 04 / MIMP / OpenStreetMap',
      sourceId: 'way/819631011',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 5,
      metadata: <String, dynamic>{'address': 'Av. Revolución s/n, V Zona'},
    ),
    _verified(
      name: 'Distribuidora e Importadora M&G S.A.C.',
      lat: -11.9136,
      lng: -77.0104,
      type: 'grifo',
      category: 'fuel',
      categoryLabel: 'Grifos / EESS',
      source: 'OSINERGMIN',
      sourceId: 'FeatureServer/35/OBJECTID/9804',
      coordinateRole: 'official_gis_point',
      zoneNumber: 5,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución 2976, Quinta Zona',
        'registryId': '44325-050-040726',
        'ruc': '20604234973',
      },
    ),
    _verified(
      name: 'Corporación Megu S.A.C.',
      lat: -11.9123,
      lng: -77.0070,
      type: 'grifo',
      category: 'fuel',
      categoryLabel: 'Grifos / EESS',
      source: 'OSINERGMIN / OpenStreetMap',
      sourceId: 'FeatureServer/35/OBJECTID/11276',
      coordinateRole: 'official_gis_point',
      zoneNumber: 5,
      metadata: <String, dynamic>{
        'address':
            'Av. Revolución con Av. María Parado de Bellido, Mz. M, lotes 34–35, V Zona',
        'registryId': '94336-056-140823',
        'ruc': '20517877574',
        'nameAliases': <String>['Grifo PECSA V Zona Megusac'],
        'aliasStatus': 'cartographic_historical_not_current_operator',
        'cartographicSourceId': 'way/874320691',
      },
    ),
    _verified(
      name: 'Cementerio Municipal Luz Eterna',
      lat: -11.9090957,
      lng: -77.0029445,
      type: 'cementerio',
      category: 'cemetery',
      categoryLabel: 'Cementerio',
      source: 'DIGESA / MINSA / OpenStreetMap',
      sourceId: 'way/466004242',
      coordinateRole: 'building_footprint_center',
      zoneNumber: 6,
      metadata: <String, dynamic>{
        'address': 'Av. Revolución, cuadra 36, VI Zona',
        'nameAliases': <String>['Cementerio de Collique'],
      },
    ),
    _verified(
      name: 'ROAN Inversiones S.A.C.',
      lat: -11.9122,
      lng: -77.0043,
      type: 'grifo',
      category: 'fuel',
      categoryLabel: 'Grifos / EESS',
      source: 'OSINERGMIN',
      sourceId: 'FeatureServer/35/OBJECTID/9834',
      coordinateRole: 'official_gis_point',
      zoneNumber: 6,
      metadata: <String, dynamic>{
        'address':
            'Av. Prolongación Revolución 3501, Mz. A, lotes 3–5, A.H. Santa Rosa de Collique',
        'registryId': '44924-050-301122',
        'ruc': '20515253883',
      },
    ),
  ]);

  static final List<Map<String, dynamic>>
  auditedPlaces = List<Map<String, dynamic>>.unmodifiable(<
    Map<String, dynamic>
  >[
    _audit(
      name: 'Puerta cartografiada del Hospital Sergio E. Bernales',
      lat: -11.9139548,
      lng: -77.0394415,
      type: 'acceso',
      category: 'health',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'Está cartografiada como puerta privada; no se confirmó como acceso público.',
      source: 'OpenStreetMap node/4345295491',
    ),
    _audit(
      name: 'Entrada o paradero Collique',
      type: 'transporte',
      category: 'transport',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'El cruce Túpac Amaru/Revolución está documentado, pero no existe un punto oficial único.',
      source: 'Agencia Andina',
    ),
    _audit(
      name: 'Puente Collique',
      lat: -11.916388,
      lng: -77.0410066,
      type: 'puente',
      category: 'transport',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'Mincetur documenta el nombre, pero la asociación con la pasarela OSM no es concluyente.',
      source: 'MINCETUR / OpenStreetMap way/435372476',
    ),
    _audit(
      name: 'Policlínico Cesmyn',
      lat: -11.9136006,
      lng: -77.0398888,
      type: 'centro_salud',
      category: 'health',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'Falta una ficha sanitaria oficial vigente concluyente.',
      source: 'OpenStreetMap node/4334133112',
    ),
    _audit(
      name: 'Mercado El Inti',
      lat: -11.9143934,
      lng: -77.029605,
      type: 'mercado',
      category: 'markets',
      zoneNumber: 2,
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'Las fuentes discrepan entre II y III Zona y no hay huella OSM coincidente.',
      source: 'Registro oficial de mercados / MINSA-DIRIS',
    ),
    _audit(
      name: 'Centro de Investigaciones Especiales Lima Norte - Collique',
      lat: -11.9144141,
      lng: -77.0289589,
      type: 'puesto',
      category: 'security',
      zoneNumber: 2,
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'No se confirmó su denominación y función vigente en 2026.',
      source: 'CODISEC 2022 / OpenStreetMap node/4208833389',
    ),
    for (final place in <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Parque Sánchez Cerro',
        'type': 'parque',
        'category': 'parks',
        'zone': 2,
        'source': 'MINSA / DIRIS VANCAN',
      },
      <String, dynamic>{
        'name': 'Losa Deportiva de la II Zona',
        'type': 'deporte',
        'category': 'sports',
        'zone': 2,
        'source': 'MINSA / DIRIS VANCAN',
      },
      <String, dynamic>{
        'name': 'Parque Guillén',
        'type': 'parque',
        'category': 'parks',
        'zone': 3,
        'source': 'MINSA / DIRIS VANCAN',
      },
      <String, dynamic>{
        'name': 'Parque N.º 4 Húsares de Junín',
        'type': 'parque',
        'category': 'parks',
        'zone': 4,
        'source': 'Municipalidad Distrital de Comas',
      },
      <String, dynamic>{
        'name': 'Losa deportiva Nueva Unión',
        'type': 'deporte',
        'category': 'sports',
        'zone': 4,
        'source': 'MINSA / DIRIS VANCAN',
      },
      <String, dynamic>{
        'name': 'Plaza Cívica de la Quinta Zona',
        'type': 'plaza',
        'category': 'social_equipment',
        'zone': 5,
        'source': 'Municipalidad Distrital de Comas',
      },
      <String, dynamic>{
        'name': 'Local Comunal Santa Rosa',
        'type': 'local_comunal',
        'category': 'social_equipment',
        'zone': 6,
        'source': 'Municipalidad Distrital de Comas',
      },
      <String, dynamic>{
        'name': 'PRONOEI Semillitas',
        'type': 'colegio',
        'category': 'education',
        'zone': 7,
        'source': 'MINEDU',
      },
      <String, dynamic>{
        'name': 'PRONOEI Casita Morada',
        'type': 'colegio',
        'category': 'education',
        'zone': 8,
        'source': 'UGEL 04',
      },
      <String, dynamic>{
        'name': 'PRONOEI Santa Rosita III',
        'type': 'colegio',
        'category': 'education',
        'zone': 8,
        'source': 'UGEL 04',
      },
    ])
      _audit(
        name: place['name'] as String,
        type: place['type'] as String,
        category: place['category'] as String,
        zoneNumber: place['zone'] as int,
        verificationStatus: partiallyVerifiedStatus,
        verificationReason:
            'Existe evidencia institucional, pero no una coordenada cartográfica exacta.',
        source: place['source'] as String,
      ),
    _audit(
      name: 'I.E. Fe y Alegría 11',
      lat: -11.9157636,
      lng: -77.0248328,
      type: 'colegio',
      category: 'education',
      zoneNumber: 3,
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'La institución y el edificio están verificados, pero su zona interna exacta no está resuelta.',
      source: 'MINEDU Identicole / OpenStreetMap way/620127520',
    ),
    _audit(
      name: 'Puesto de Salud Milagro de Jesús',
      lat: -11.9186979,
      lng: -77.0258659,
      type: 'centro_salud',
      category: 'health',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'La IPRESS y el punto existen; falta resolver su zona interna.',
      source: 'DIRIS Lima Norte / OpenStreetMap node/6864295875',
    ),
    _audit(
      name: 'Parroquia Cristo Luz del Mundo',
      lat: -11.9140518,
      lng: -77.0247517,
      type: 'iglesia',
      category: 'culture',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'No se obtuvo una dirección institucional actual concluyente.',
      source: 'Registro estatal / OpenStreetMap node/4945684461',
    ),
    _audit(
      name: 'I.E. Coronel José Gálvez',
      lat: -11.9110857,
      lng: -77.0146966,
      type: 'colegio',
      category: 'education',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'La institución está verificada, pero la fuente oficial no fija la zona interna.',
      source: 'UGEL 04 / OpenStreetMap way/819644986',
    ),
    _audit(
      name: 'I.E. 3076 Santa Rosa',
      lat: -11.9104624,
      lng: -77.0055268,
      type: 'colegio',
      category: 'education',
      verificationStatus: partiallyVerifiedStatus,
      verificationReason: 'Las fuentes discrepan entre V y VI Zona.',
      source: 'MINEDU Identicole / PRONIED / OpenStreetMap way/819629821',
    ),
    _audit(
      name: 'Inicio o terminal Río Seco de alimentadora Collique',
      lat: -11.9124257,
      lng: -77.0047422,
      type: 'transporte',
      category: 'transport',
      zoneNumber: 6,
      verificationStatus: partiallyVerifiedStatus,
      verificationReason:
          'No se encontró padrón vigente de plataformas para 2026.',
      source: 'ATU / OpenStreetMap node/13372954533',
    ),
    for (final rejected in <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Comisaría PNP La Pascana',
        'lat': -11.9349512,
        'lng': -77.0458428,
        'source': 'OpenStreetMap way/318951901',
      },
      <String, dynamic>{
        'name': 'Comisaría PNP Santa Luzmila',
        'lat': -11.9444057,
        'lng': -77.0662845,
        'source': 'OpenStreetMap way/318949849',
      },
      <String, dynamic>{
        'name': 'Comisaría PNP Universitaria',
        'lat': -11.9474565,
        'lng': -77.0599981,
        'source': 'OpenStreetMap way/318954668',
      },
    ])
      _audit(
        name: rejected['name'] as String,
        lat: rejected['lat'] as double,
        lng: rejected['lng'] as double,
        type: 'comisaria',
        category: 'security',
        verificationStatus: rejectedStatus,
        verificationReason: 'Lugar real, pero fuera del ámbito de Collique.',
        source: rejected['source'] as String,
      ),
    _audit(
      name: 'Parque Central de Collique',
      lat: -11.9067937,
      lng: -77.0347333,
      type: 'parque',
      category: 'parks',
      verificationStatus: rejectedStatus,
      verificationReason:
          'El objeto OSM se llama Parque Central; el sufijo de Collique no está respaldado.',
      source: 'OpenStreetMap way/593084550',
    ),
    _audit(
      name: 'Comisaría PNP Comas Collique - pin heredado',
      lat: -11.92138,
      lng: -77.02264,
      type: 'comisaria',
      category: 'security',
      verificationStatus: rejectedStatus,
      verificationReason:
          'La coordenada no corresponde al edificio de la Comisaría PNP Collique.',
      source: 'Datos heredados del proyecto',
    ),
    _audit(
      name: 'Uvita',
      type: 'transporte',
      category: 'transport',
      verificationStatus: rejectedStatus,
      verificationReason: 'El servicio cesó permanentemente en abril de 2026.',
      source: 'TV Perú / RPP',
    ),
    for (final stopName in <String>[
      'Paradero Julio C. Tello',
      'Paradero Arica',
      'Paradero Cerro de Pasco',
      'Paradero Ramón Castilla',
      'Paradero Francisco de Zela',
    ])
      _audit(
        name: stopName,
        type: 'transporte',
        category: 'transport',
        verificationStatus: unverifiedStatus,
        verificationReason:
            'Existe referencia cartográfica, pero no un padrón ATU vigente.',
        source: 'OpenStreetMap',
      ),
  ]);

  static bool isProductionPoi(Map<String, dynamic> poi) {
    return poi['verified'] == true &&
        poi['verificationStatus'] == verifiedStatus &&
        poi['productionVisible'] == true &&
        poi['lat'] is double &&
        poi['lng'] is double;
  }

  static List<Map<String, dynamic>> byCategory(String category) {
    return List<Map<String, dynamic>>.unmodifiable(
      productionPois.where((poi) => poi['category'] == category),
    );
  }

  static List<Map<String, dynamic>> auditedByStatus(String status) {
    return List<Map<String, dynamic>>.unmodifiable(
      auditedPlaces.where((poi) => poi['verificationStatus'] == status),
    );
  }
}
