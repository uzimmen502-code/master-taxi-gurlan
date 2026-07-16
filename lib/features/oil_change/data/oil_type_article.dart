// Moy turlari batafsil maqolalari (mineral/semi/full) — «Мой турлари» ekrani
// detal varag'i uchun. Manba (source of truth): docs/oil_change_app.html TYPE_DETAILS.
// Har bir matn 3 tilda (L3): uz_Cyrl / uz_Latn / ru. Blok-asosli model → faithful render.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import 'oil_l10n.dart';

sealed class OilArtBlock {
  const OilArtBlock();
}

class ArtHero extends OilArtBlock {
  const ArtHero(this.text, [this.color = const Color(0xFF1A2E1C)]);
  final L3 text;
  final Color color;
}

class ArtLead extends OilArtBlock {
  const ArtLead(this.text);
  final L3 text;
}

class ArtPara extends OilArtBlock {
  const ArtPara(this.text, {this.bold = false});
  final L3 text;
  final bool bold;
}

class ArtHeading extends OilArtBlock {
  const ArtHeading(this.text);
  final L3 text;
}

class ArtCheck extends OilArtBlock {
  const ArtCheck(this.items);
  final List<L3> items;
}

class ArtPros extends OilArtBlock {
  const ArtPros(this.items);
  final List<L3> items;
}

class ArtCons extends OilArtBlock {
  const ArtCons(this.items);
  final List<L3> items;
}

class ArtBrands extends OilArtBlock {
  const ArtBrands(this.items);
  final List<L3> items;
}

class ArtWhen extends OilArtBlock {
  const ArtWhen(this.items, {this.verdict});
  final List<L3> items;
  final L3? verdict;
}

class ArtKm extends OilArtBlock {
  const ArtKm(this.cards);
  final List<(L3, L3, L3?)> cards;
}

class ArtSafe extends OilArtBlock {
  const ArtSafe(this.title, this.body);
  final L3 title;
  final L3 body;
}

class ArtGas extends OilArtBlock {
  const ArtGas({
    required this.tag,
    this.paras = const [],
    this.bullets = const [],
    this.positive = false,
  });
  final L3 tag;
  final List<L3> paras;
  final List<L3> bullets;
  final bool positive;
}

class ArtSae extends OilArtBlock {
  const ArtSae(this.pills);

  /// (SAE kodi — neytral, izoh — L3).
  final List<(String, L3)> pills;
}

class ArtSimple extends OilArtBlock {
  const ArtSimple(this.label, this.lines, this.balance);
  final L3 label;
  final List<L3> lines;
  final L3 balance;
}

class ArtKeyTip extends OilArtBlock {
  const ArtKeyTip({
    required this.quote,
    this.before,
    this.specs = const [],
    this.after,
  });
  final L3 quote;
  final L3? before;
  final List<L3> specs;
  final L3? after;
}

class ArtCompare extends OilArtBlock {
  const ArtCompare(this.headers, this.rows);
  final List<L3> headers;
  final List<List<L3>> rows;
}

class OilTypeArticle {
  const OilTypeArticle(this.blocks);
  final List<OilArtBlock> blocks;
}

OilTypeArticle? oilTypeArticle(String key) => _articles[key];

// ── Umumiy (qayta ishlatiluvchi) matnlar ────────────────────────────
const _kmTitle = L3(
  'Қанча километр юриш мумкин?',
  'Qancha kilometr yurish mumkin?',
  'Сколько километров можно проехать?',
);
const _forDriver = L3('Оддий ҳайдовчи учун:', 'Oddiy haydovchi uchun:',
    'Для обычного водителя:');
const _safeTitle =
    L3('Энг хавфсиз қоида', 'Eng xavfsiz qoida', 'Самое безопасное правило');
const _gasTitle = L3('Газ бўлсачи?', 'Gaz bo‘lsachi?', 'А если газ?');
const _gasTag = L3('МЕТАН / ПРОПАН', 'METAN / PROPAN', 'МЕТАН / ПРОПАН');
const _pros = L3('Афзалликлари', 'Afzalliklari', 'Преимущества');
const _cons = L3('Камчиликлари', 'Kamchiliklari', 'Недостатки');
const _cityMineral = L3('Шаҳарда', 'Shaharda', 'В городе');
const _mixed = L3('Аралаш режим', 'Aralash rejim', 'Смешанный режим');
const _trassa = L3('Асосан трасса', 'Asosan trassa', 'В основном трасса');
const _specSae = L3('тўғри SAE', 'to‘g‘ri SAE', 'правильный SAE');
const _specApi = L3('тўғри API', 'to‘g‘ri API', 'правильный API');
const _specAcea = L3('тўғри ACEA', 'to‘g‘ri ACEA', 'правильный ACEA');
const _specOem = L3('OEM спецификация', 'OEM spetsifikatsiya', 'спецификация OEM');

const _articles = <String, OilTypeArticle>{
  'mineral': OilTypeArticle([
    ArtHero(
      L3('Минерал мой нима?', 'Mineral moy nima?',
          'Что такое минеральное масло?'),
      Color(0xFF5D4037),
    ),
    ArtLead(L3(
      'Минерал мотор мойи — бу нефтдан тозаланиб олинадиган энг оддий мотор мойи.',
      'Mineral motor moyi — bu neftdan tozalanib olinadigan eng oddiy motor moyi.',
      'Минеральное моторное масло — это самое простое моторное масло, получаемое очисткой из нефти.',
    )),
    ArtPara(L3(
      'Унинг таркиби табиий нефтга асосланган бўлиб, синтетик мойларга қараганда камроқ қайта ишланган.',
      'Uning tarkibi tabiiy neftga asoslangan bo‘lib, sintetik moylarga qaraganda kamroq qayta ishlangan.',
      'Его состав основан на природной нефти и обработан меньше, чем синтетические масла.',
    )),
    ArtPara(L3(
      'Минерал мой илгари деярли барча автомобилларда ишлатилган. Ҳозир эса асосан эски автомобиллар ва оддий двигателлар учун тавсия қилинади.',
      'Mineral moy ilgari deyarli barcha avtomobillarda ishlatilgan. Hozir esa asosan eski avtomobillar va oddiy dvigatellar uchun tavsiya qilinadi.',
      'Раньше минеральное масло использовали почти во всех автомобилях. Сейчас его рекомендуют в основном для старых авто и простых двигателей.',
    )),
    ArtHeading(L3('Нима учун минерал мой қуйилади?',
        'Nima uchun mineral moy quyiladi?', 'Зачем заливают минеральное масло?')),
    ArtPara(
      L3('Минерал мойнинг асосий афзалликлари:',
          'Mineral moyning asosiy afzalliklari:',
          'Основные преимущества минерального масла:'),
      bold: true,
    ),
    ArtCheck([
      L3('Нархи энг арзон.', 'Narxi eng arzon.', 'Самая низкая цена.'),
      L3('Эски двигателларда яхши ишлайди.',
          'Eski dvigatellarda yaxshi ishlaydi.',
          'Хорошо работает в старых двигателях.'),
      L3('Эски резина сальниклардан сизиб чиқиш эҳтимоли камроқ.',
          'Eski rezina salniklardan sizib chiqish ehtimoli kamroq.',
          'Меньше вероятность подтёков через старые резиновые сальники.'),
      L3('Таъмирлаш харажатини камайтиради.',
          'Ta’mirlash xarajatini kamaytiradi.', 'Снижает расходы на ремонт.'),
    ]),
    ArtHeading(L3('Қайси автомобилларга мос?', 'Qaysi avtomobillarga mos?',
        'Каким автомобилям подходит?')),
    ArtPara(L3(
      'Минерал мой асосан қуйидагилар учун мос бўлиши мумкин (агар ишлаб чиқарувчи рухсат берган бўлса):',
      'Mineral moy asosan quyidagilar uchun mos bo‘lishi mumkin (agar ishlab chiqaruvchi ruxsat bergan bo‘lsa):',
      'Минеральное масло в основном может подойти для следующих (если производитель допускает):',
    )),
    ArtBrands([
      L3('Damas', 'Damas', 'Damas'),
      L3('Labo', 'Labo', 'Labo'),
      L3('Matiz (эски)', 'Matiz (eski)', 'Matiz (старый)'),
      L3('Nexia 1', 'Nexia 1', 'Nexia 1'),
      L3('Nexia 2', 'Nexia 2', 'Nexia 2'),
      L3('Tico', 'Tico', 'Tico'),
      L3('Москвич', 'Moskvich', 'Москвич'),
      L3('Жигули (VAZ)', 'Jiguli (VAZ)', 'Жигули (ВАЗ)'),
      L3('Волга', 'Volga', 'Волга'),
      L3('УАЗ', 'UAZ', 'УАЗ'),
      L3('эски автомобиллар', 'eski avtomobillar', 'старые автомобили'),
    ]),
    ArtHeading(L3('Қачон минерал мой қуйиш мумкин?',
        'Qachon mineral moy quyish mumkin?',
        'Когда можно заливать минеральное масло?')),
    ArtWhen([
      L3('автомобил анча эски бўлса;', 'avtomobil ancha eski bo‘lsa;',
          'автомобиль довольно старый;'),
      L3('двигател конструкцияси содда бўлса;',
          'dvigatel konstruksiyasi sodda bo‘lsa;',
          'конструкция двигателя простая;'),
      L3('турбина бўлмаса;', 'turbina bo‘lmasa;', 'нет турбины;'),
      L3('ишлаб чиқарувчи минерал мойга рухсат берган бўлса.',
          'ishlab chiqaruvchi mineral moyga ruxsat bergan bo‘lsa.',
          'производитель допускает минеральное масло.'),
    ]),
    ArtHeading(_kmTitle),
    ArtPara(L3('Бу энг кўп бериладиган савол.',
        'Bu eng ko‘p beriladigan savol.', 'Это самый частый вопрос.')),
    ArtPara(_forDriver, bold: true),
    ArtKm([
      (_cityMineral, L3('4 000–5 000 км', '4 000–5 000 km', '4 000–5 000 км'),
          null),
      (_mixed, L3('5 000–6 000 км', '5 000–6 000 km', '5 000–6 000 км'), null),
      (_trassa, L3('6 000–7 000 км', '6 000–7 000 km', '6 000–7 000 км'), null),
    ]),
    ArtSafe(
      _safeTitle,
      L3('Минерал мойни 5 000 км дан оширмаслик.',
          'Mineral moyni 5 000 km dan oshirmaslik.',
          'Не превышать 5 000 км на минеральном масле.'),
    ),
    ArtHeading(_gasTitle),
    ArtGas(
      tag: _gasTag,
      paras: [
        L3('Газда двигател ҳарорати юқорироқ бўлади. Минерал мой бундай шароитда тезроқ эскиради.',
            'Gazda dvigatel harorati yuqoriroq bo‘ladi. Mineral moy bunday sharoitda tezroq eskiradi.',
            'На газе температура двигателя выше. Минеральное масло в таких условиях стареет быстрее.'),
        L3('Шунинг учун газли автомобилларда минерал мой тавсия этилмайди.',
            'Shuning uchun gazli avtomobillarda mineral moy tavsiya etilmaydi.',
            'Поэтому в газовых автомобилях минеральное масло не рекомендуется.'),
        L3('Агар бошқа имконият бўлмаса, 5 000 км атрофида алмаштириш мақсадга мувофиқ.',
            'Agar boshqa imkoniyat bo‘lmasa, 5 000 km atrofida almashtirish maqsadga muvofiq.',
            'Если другого варианта нет, замену целесообразно делать около 5 000 км.'),
      ],
    ),
    ArtHeading(L3('Қайси қуюқлик (SAE) кўп учрайди?',
        'Qaysi quyuqlik (SAE) ko‘p uchraydi?',
        'Какая вязкость (SAE) встречается чаще?')),
    ArtSae([
      ('10W-40', L3('энг оммабоп вариантлардан', 'eng ommabop variantlardan',
          'из самых популярных вариантов')),
      ('15W-40', L3('энг оммабоп вариантлардан', 'eng ommabop variantlardan',
          'из самых популярных вариантов')),
      ('20W-50', L3('энг оммабоп вариантлардан', 'eng ommabop variantlardan',
          'из самых популярных вариантов')),
    ]),
    ArtPara(L3(
      'Совуқ ҳудудларда 20W мой қийин айланиши мумкин, шунинг учун иқлимни ҳам ҳисобга олиш лозим.',
      'Sovuq hududlarda 20W moy qiyin aylanishi mumkin, shuning uchun iqlimni ham hisobga olish lozim.',
      'В холодных регионах масло 20W может проворачиваться тяжело, поэтому нужно учитывать климат.',
    )),
    ArtHeading(_pros),
    ArtPros([
      L3('Энг арзон.', 'Eng arzon.', 'Самое дешёвое.'),
      L3('Эски двигателлар учун яхши.', 'Eski dvigatellar uchun yaxshi.',
          'Хорошо для старых двигателей.'),
      L3('Мой сарфи юқори бўлган двигателларда баъзан фойдали.',
          'Moy sarfi yuqori bo‘lgan dvigatellarda ba’zan foydali.',
          'Иногда полезно в двигателях с высоким расходом масла.'),
      L3('Харид қилиш осон.', 'Xarid qilish oson.', 'Легко купить.'),
    ]),
    ArtHeading(_cons),
    ArtCons([
      L3('Тез эскиради.', 'Tez eskiradi.', 'Быстро стареет.'),
      L3('Совуқда яхши ишламайди.', 'Sovuqda yaxshi ishlamaydi.',
          'Плохо работает на холоде.'),
      L3('Иссиқда тезроқ хусусиятини йўқотади.',
          'Issiqda tezroq xususiyatini yo‘qotadi.',
          'В жару быстрее теряет свойства.'),
      L3('Двигателни синтетика каби яхши тозаламайди.',
          'Dvigatelni sintetika kabi yaxshi tozalamaydi.',
          'Очищает двигатель хуже, чем синтетика.'),
      L3('Янги автомобиллар учун кўп ҳолларда мос эмас.',
          'Yangi avtomobillar uchun ko‘p hollarda mos emas.',
          'Для новых авто в большинстве случаев не подходит.'),
    ]),
    ArtKeyTip(
      quote: L3(
        'Кўпчилик «Минерал мой арзон экан, шуни қуя қоламан» деб ўйлайди. Бу ҳар доим ҳам тўғри эмас.',
        'Ko‘pchilik «Mineral moy arzon ekan, shuni quya qolaman» deb o‘ylaydi. Bu har doim ham to‘g‘ri emas.',
        'Многие думают: «Минеральное дешёвое, залью его». Это не всегда правильно.',
      ),
      before: L3('Автомобилингиз учун биринчи ўринда:',
          'Avtomobilingiz uchun birinchi o‘rinda:',
          'Для вашего автомобиля в первую очередь важны:'),
      specs: [_specSae, _specApi, _specAcea, _specOem],
      after: L3(
        'Арзон мой қуйиб, кейин двигателни таъмирлаш анча қимматга тушиши мумкин.',
        'Arzon moy quyib, keyin dvigatelni ta’mirlash ancha qimmatga tushishi mumkin.',
        'Залить дешёвое масло, а потом ремонтировать двигатель может выйти намного дороже.',
      ),
    ),
  ]),
  'semi': OilTypeArticle([
    ArtHero(L3('Ярим синтетик мой нима?', 'Yarim sintetik moy nima?',
        'Что такое полусинтетическое масло?')),
    ArtLead(L3(
      'Ярим синтетик мой — бу минерал мой билан тўлиқ синтетик мойнинг аралашмаси.',
      'Yarim sintetik moy — bu mineral moy bilan to‘liq sintetik moyning aralashmasi.',
      'Полусинтетическое масло — это смесь минерального и полностью синтетического масла.',
    )),
    ArtSimple(
      L3('Оддий қилиб айтганда', 'Oddiy qilib aytganda', 'Проще говоря'),
      [
        L3('Минерал мой — энг арзон, лекин тез эскиради.',
            'Mineral moy — eng arzon, lekin tez eskiradi.',
            'Минеральное — самое дешёвое, но быстро стареет.'),
        L3('Тўлиқ синтетик мой — энг сифатли, лекин қиммат.',
            'To‘liq sintetik moy — eng sifatli, lekin qimmat.',
            'Полная синтетика — самое качественное, но дорогое.'),
      ],
      L3('Ярим синтетик мой — шу иккисининг ўртасидаги энг яхши мувозанат.',
          'Yarim sintetik moy — shu ikkisining o‘rtasidagi eng yaxshi muvozanat.',
          'Полусинтетика — лучший баланс между этими двумя.'),
    ),
    ArtPara(L3(
      'Шунинг учун кўпчилик ҳайдовчилар айнан ярим синтетик мойдан фойдаланади.',
      'Shuning uchun ko‘pchilik haydovchilar aynan yarim sintetik moydan foydalanadi.',
      'Поэтому большинство водителей используют именно полусинтетику.',
    )),
    ArtHeading(L3('Нима учун ярим синтетик мой қуйилади?',
        'Nima uchun yarim sintetik moy quyiladi?',
        'Зачем заливают полусинтетику?')),
    ArtCheck([
      L3('Минерал мойдан яхшироқ ҳимоя қилади.',
          'Mineral moydan yaxshiroq himoya qiladi.',
          'Защищает лучше минерального.'),
      L3('Совуқда двигатель енгилроқ ишга тушади.',
          'Sovuqda dvigatel yengilroq ishga tushadi.',
          'На холоде двигатель запускается легче.'),
      L3('Иссиқда тез суюлиб кетмайди.', 'Issiqda tez suyulib ketmaydi.',
          'В жару не разжижается быстро.'),
      L3('Двигател ичидаги кирларни яхши тозалайди.',
          'Dvigatel ichidagi kirlarni yaxshi tozalaydi.',
          'Хорошо очищает загрязнения внутри двигателя.'),
      L3('Нархи синтетикадан арзон.', 'Narxi sintetikadan arzon.',
          'Дешевле синтетики.'),
    ]),
    ArtHeading(L3('Қачон ярим синтетик мой қуйиш керак?',
        'Qachon yarim sintetik moy quyish kerak?',
        'Когда нужно заливать полусинтетику?')),
    ArtWhen(
      [
        L3('автомобил 5–10 йиллик бўлса;', 'avtomobil 5–10 yillik bo‘lsa;',
            'автомобилю 5–10 лет;'),
        L3('двигател яхши ишлаётган бўлса;',
            'dvigatel yaxshi ishlayotgan bo‘lsa;',
            'двигатель работает исправно;'),
        L3('кунига оддий юришлар бўлса;', 'kuniga oddiy yurishlar bo‘lsa;',
            'ежедневные обычные поездки;'),
        L3('спорт режимида юрилмаса,', 'sport rejimida yurilmasa,',
            'нет езды в спортивном режиме,'),
      ],
      verdict: L3('ярим синтетик мой жуда яхши танлов ҳисобланади.',
          'yarim sintetik moy juda yaxshi tanlov hisoblanadi.',
          'полусинтетика — очень хороший выбор.'),
    ),
    ArtHeading(_kmTitle),
    ArtPara(L3('Бу ҳайдовчилар энг кўп берадиган савол.',
        'Bu haydovchilar eng ko‘p beradigan savol.',
        'Это самый частый вопрос водителей.')),
    ArtPara(_forDriver, bold: true),
    ArtKm([
      (L3('Шаҳарда кўп', 'Shaharda ko‘p', 'Много по городу'),
          L3('6 000–7 000 км', '6 000–7 000 km', '6 000–7 000 км'), null),
      (L3('Аралаш (шаҳар + трасса)', 'Aralash (shahar + trassa)',
          'Смешанный (город + трасса)'),
          L3('7 000–8 000 км', '7 000–8 000 km', '7 000–8 000 км'), null),
      (_trassa, L3('8 000–10 000 км', '8 000–10 000 km', '8 000–10 000 км'),
          L3('агар мой ва автомобил шунга мос бўлса',
              'agar moy va avtomobil shunga mos bo‘lsa',
              'если масло и авто это позволяют')),
    ]),
    ArtSafe(
      _safeTitle,
      L3('Ярим синтетик мойни 7 000 км атрофида алмаштириш.',
          'Yarim sintetik moyni 7 000 km atrofida almashtirish.',
          'Менять полусинтетику примерно на 7 000 км.'),
    ),
    ArtHeading(_gasTitle),
    ArtGas(
      tag: _gasTag,
      paras: [
        L3('Газда двигатель ҳарорати юқорироқ бўлади.',
            'Gazda dvigatel harorati yuqoriroq bo‘ladi.',
            'На газе температура двигателя выше.'),
        L3('Газли автомобилда ярим синтетик учун 6 000–7 000 км атрофида алмаштириш мақсадга мувофиқ.',
            'Gazli avtomobilda yarim sintetik uchun 6 000–7 000 km atrofida almashtirish maqsadga muvofiq.',
            'В газовом авто полусинтетику целесообразно менять около 6 000–7 000 км.'),
      ],
      bullets: [
        L3('мойни кечиктирмасдан алмаштиринг;',
            'moyni kechiktirmasdan almashtiring;',
            'меняйте масло без задержек;'),
        L3('имкони бўлса, тўлиқ синтетик мойдан фойдаланинг.',
            'imkoni bo‘lsa, to‘liq sintetik moydan foydalaning.',
            'при возможности используйте полную синтетику.'),
      ],
    ),
    ArtHeading(L3('Қайси қуюқлик (SAE) танланади?',
        'Qaysi quyuqlik (SAE) tanlanadi?', 'Какую вязкость (SAE) выбрать?')),
    ArtSae([
      ('5W-30', L3('янги ёки яхши ҳолатдаги двигателлар учун',
          'yangi yoki yaxshi holatdagi dvigatellar uchun',
          'для новых или исправных двигателей')),
      ('5W-40', L3('иссиқ иқлим ва турли шароитлар учун оммабоп вариант',
          'issiq iqlim va turli sharoitlar uchun ommabop variant',
          'популярный вариант для жаркого климата и разных условий')),
      ('10W-40', L3('эскироқ автомобиллар учун энг машҳур ярим синтетик мой',
          'eskiroq avtomobillar uchun eng mashhur yarim sintetik moy',
          'самая популярная полусинтетика для авто постарше')),
    ]),
    ArtHeading(_pros),
    ArtPros([
      L3('Нархи арзонроқ.', 'Narxi arzonroq.', 'Цена ниже.'),
      L3('Двигателни яхши ҳимоя қилади.', 'Dvigatelni yaxshi himoya qiladi.',
          'Хорошо защищает двигатель.'),
      L3('Минерал мойдан узоқроқ хизмат қилади.',
          'Mineral moydan uzoqroq xizmat qiladi.',
          'Служит дольше минерального.'),
      L3('Совуқда яхши ишлайди.', 'Sovuqda yaxshi ishlaydi.',
          'Хорошо работает на холоде.'),
      L3('Иссиқда ҳам барқарор.', 'Issiqda ham barqaror.',
          'Стабильно и в жару.'),
      L3('Кўпчилик автомобиллар учун етарли.',
          'Ko‘pchilik avtomobillar uchun yetarli.',
          'Достаточно для большинства авто.'),
    ]),
    ArtHeading(_cons),
    ArtCons([
      L3('Синтетикачалик узоқ хизмат қилмайди.',
          'Sintetikachalik uzoq xizmat qilmaydi.',
          'Служит не так долго, как синтетика.'),
      L3('Турбо двигателлар учун ҳамма вақт тўғри танлов эмас.',
          'Turbo dvigatellar uchun hamma vaqt to‘g‘ri tanlov emas.',
          'Не всегда верный выбор для турбодвигателей.'),
      L3('Жуда юқори ҳароратда тезроқ эскиради.',
          'Juda yuqori haroratda tezroq eskiradi.',
          'При очень высокой температуре стареет быстрее.'),
    ]),
    ArtKeyTip(
      quote: L3(
        'Кўпчилик «қайси бренд яхши?» деб сўрайди. Аслида энг муҳими бренд эмас.',
        'Ko‘pchilik «qaysi brend yaxshi?» deb so‘raydi. Aslida eng muhimi brend emas.',
        'Многие спрашивают «какой бренд лучше?». На самом деле главное — не бренд.',
      ),
      before: L3('Автомобилингиз учун мос бўлиши керак:',
          'Avtomobilingiz uchun mos bo‘lishi kerak:',
          'Для вашего авто должны подходить:'),
      specs: [_specSae, _specApi, _specAcea, _specOem],
    ),
  ]),
  'full': OilTypeArticle([
    ArtHero(
      L3('Тўлиқ синтетик мой нима?', 'To‘liq sintetik moy nima?',
          'Что такое полностью синтетическое масло?'),
      Color(0xFF1B7A28),
    ),
    ArtLead(L3(
      'Тўлиқ синтетик мотор мойи (Full Synthetic) — бу замонавий технологиялар асосида ишлаб чиқарилган энг юқори сифатли мотор мойи.',
      'To‘liq sintetik motor moyi (Full Synthetic) — bu zamonaviy texnologiyalar asosida ishlab chiqarilgan eng yuqori sifatli motor moyi.',
      'Полностью синтетическое моторное масло (Full Synthetic) — это масло высшего качества, произведённое на основе современных технологий.',
    )),
    ArtPara(L3(
      'У оддий минерал мойдан фарқли равишда махсус тозаланган ва кимёвий жиҳатдан барқарор база мойларидан тайёрланади.',
      'U oddiy mineral moydan farqli ravishda maxsus tozalangan va kimyoviy jihatdan barqaror baza moylaridan tayyorlanadi.',
      'В отличие от обычного минерального, оно изготавливается из специально очищенных и химически стабильных базовых масел.',
    )),
    ArtHeading(L3('Нима учун тўлиқ синтетик мой қуйилади?',
        'Nima uchun to‘liq sintetik moy quyiladi?',
        'Зачем заливают полную синтетику?')),
    ArtCheck([
      L3('Двигателни энг яхши ҳимоя қилади.',
          'Dvigatelni eng yaxshi himoya qiladi.',
          'Защищает двигатель лучше всего.'),
      L3('Совуқда ҳам осон айланади.', 'Sovuqda ham oson aylanadi.',
          'Легко проворачивается даже на холоде.'),
      L3('Иссиқда ҳам қуюқлигини яхши сақлайди.',
          'Issiqda ham quyuqligini yaxshi saqlaydi.',
          'Хорошо сохраняет вязкость и в жару.'),
      L3('Турбина учун жуда яхши.', 'Turbina uchun juda yaxshi.',
          'Отлично для турбины.'),
      L3('Мой камроқ буғланади.', 'Moy kamroq bug‘lanadi.',
          'Масло меньше испаряется.'),
      L3('Двигателни тозароқ сақлайди.', 'Dvigatelni tozaroq saqlaydi.',
          'Содержит двигатель чище.'),
      L3('Узоқроқ хизмат қилади.', 'Uzoqroq xizmat qiladi.', 'Служит дольше.'),
    ]),
    ArtHeading(L3('Қачон тўлиқ синтетик мой қуйиш керак?',
        'Qachon to‘liq sintetik moy quyish kerak?',
        'Когда нужно заливать полную синтетику?')),
    ArtWhen([
      L3('автомобил янги бўлса;', 'avtomobil yangi bo‘lsa;',
          'автомобиль новый;'),
      L3('турбо двигател бўлса;', 'turbo dvigatel bo‘lsa;', 'турбодвигатель;'),
      L3('гибрид автомобил бўлса;', 'gibrid avtomobil bo‘lsa;',
          'гибридный автомобиль;'),
      L3('GDI (тўғридан-тўғри пуркаш) двигател бўлса;',
          'GDI (to‘g‘ridan-to‘g‘ri purkash) dvigatel bo‘lsa;',
          'двигатель GDI (прямой впрыск);'),
      L3('ишлаб чиқарувчи Full Synthetic талаб қилган бўлса.',
          'ishlab chiqaruvchi Full Synthetic talab qilgan bo‘lsa.',
          'производитель требует Full Synthetic.'),
    ]),
    ArtHeading(_kmTitle),
    ArtPara(L3(
      'Бу мойнинг сифатига ва автомобил ишлаб чиқарувчисининг талабига боғлиқ.',
      'Bu moyning sifatiga va avtomobil ishlab chiqaruvchisining talabiga bog‘liq.',
      'Это зависит от качества масла и требований производителя автомобиля.',
    )),
    ArtPara(_forDriver, bold: true),
    ArtKm([
      (_cityMineral, L3('8 000–10 000 км', '8 000–10 000 km', '8 000–10 000 км'),
          null),
      (_mixed, L3('10 000–12 000 км', '10 000–12 000 km', '10 000–12 000 км'),
          null),
      (_trassa, L3('12 000–15 000 км', '12 000–15 000 km', '12 000–15 000 км'),
          L3('агар ишлаб чиқарувчи рухсат берса',
              'agar ishlab chiqaruvchi ruxsat bersa',
              'если производитель допускает')),
    ]),
    ArtSafe(
      _safeTitle,
      L3('Ўзбекистон шароитида тўлиқ синтетик мойни 10 000 км атрофида алмаштириш кўпчилик автомобиллар учун яхши амалиёт.',
          'O‘zbekiston sharoitida to‘liq sintetik moyni 10 000 km atrofida almashtirish ko‘pchilik avtomobillar uchun yaxshi amaliyot.',
          'В условиях Узбекистана замена полной синтетики около 10 000 км — хорошая практика для большинства авто.'),
    ),
    ArtHeading(_gasTitle),
    ArtGas(
      tag: _gasTag,
      positive: true,
      paras: [
        L3('Газли автомобиллар учун тўлиқ синтетик мой энг яхши танловлардан бири.',
            'Gazli avtomobillar uchun to‘liq sintetik moy eng yaxshi tanlovlardan biri.',
            'Для газовых автомобилей полная синтетика — один из лучших выборов.'),
      ],
      bullets: [
        L3('юқори ҳароратга чидамли;', 'yuqori haroratga chidamli;',
            'устойчива к высокой температуре;'),
        L3('камроқ буғланади;', 'kamroq bug‘lanadi;', 'меньше испаряется;'),
        L3('узоқроқ хизмат қилади;', 'uzoqroq xizmat qiladi;',
            'служит дольше;'),
        L3('двигателни яхшироқ ҳимоя қилади.',
            'dvigatelni yaxshiroq himoya qiladi.',
            'лучше защищает двигатель.'),
      ],
    ),
    ArtHeading(L3('Қайси қуюқлик (SAE) кўп учрайди?',
        'Qaysi quyuqlik (SAE) ko‘p uchraydi?',
        'Какая вязкость (SAE) встречается чаще?')),
    ArtSae([
      ('0W-20', L3('энг машҳурларидан', 'eng mashhurlaridan',
          'из самых популярных')),
      ('0W-30', L3('энг машҳурларидан', 'eng mashhurlaridan',
          'из самых популярных')),
      ('5W-30', L3('энг машҳурларидан', 'eng mashhurlaridan',
          'из самых популярных')),
      ('5W-40', L3('энг машҳурларидан', 'eng mashhurlaridan',
          'из самых популярных')),
      ('0W-40', L3('энг машҳурларидан', 'eng mashhurlaridan',
          'из самых популярных')),
    ]),
    ArtPara(L3(
      'Қайси бири тўғри эканини автомобил қўлланмаси белгилайди.',
      'Qaysi biri to‘g‘ri ekanini avtomobil qo‘llanmasi belgilaydi.',
      'Какой именно подходит — определяет руководство по автомобилю.',
    )),
    ArtHeading(_pros),
    ArtPros([
      L3('Энг яхши ҳимоя.', 'Eng yaxshi himoya.', 'Лучшая защита.'),
      L3('Совуқда енгил ишга туширади.', 'Sovuqda yengil ishga tushiradi.',
          'Лёгкий пуск на холоде.'),
      L3('Иссиқда барқарор.', 'Issiqda barqaror.', 'Стабильно в жару.'),
      L3('Турбина учун жуда яхши.', 'Turbina uchun juda yaxshi.',
          'Отлично для турбины.'),
      L3('Камроқ мой сарфлайди.', 'Kamroq moy sarflaydi.',
          'Меньше расход масла.'),
      L3('Двигателни тоза сақлайди.', 'Dvigatelni toza saqlaydi.',
          'Содержит двигатель в чистоте.'),
      L3('Узоқ хизмат қилади.', 'Uzoq xizmat qiladi.', 'Служит долго.'),
      L3('Ёқилғи тежашга ёрдам бериши мумкин.',
          'Yoqilg‘i tejashga yordam berishi mumkin.',
          'Может помочь экономить топливо.'),
    ]),
    ArtHeading(_cons),
    ArtCons([
      L3('Нархи юқорироқ.', 'Narxi yuqoriroq.', 'Цена выше.'),
      L3('Эски, мой сизиб чиқадиган двигателларда баъзан сизишни аниқроқ намоён қилиши мумкин (мой айби эмас — муҳрлар/сальниклар ҳолати).',
          'Eski, moy sizib chiqadigan dvigatellarda ba’zan sizishni aniqroq namoyon qilishi mumkin (moy aybi emas — muhrlar/salniklar holati).',
          'В старых двигателях с подтёками иногда может сильнее проявить течь (это не вина масла — состояние сальников/уплотнений).'),
      L3('Ҳамма эски автомобилларга ҳам зарур эмас.',
          'Hamma eski avtomobillarga ham zarur emas.',
          'Нужна не всем старым автомобилям.'),
    ]),
    ArtKeyTip(
      quote: L3(
        '«Энг қиммат мойни қуйсам, двигател энг яхши ишлайди» — бу ҳар доим ҳам тўғри эмас.',
        '«Eng qimmat moyni quysam, dvigatel eng yaxshi ishlaydi» — bu har doim ham to‘g‘ri emas.',
        '«Залью самое дорогое масло — двигатель будет работать лучше всего» — это не всегда так.',
      ),
      before: L3('Энг яхши мой — бу:', 'Eng yaxshi moy — bu:',
          'Лучшее масло — это:'),
      specs: [
        _specSae,
        _specApi,
        L3('ACEA / ILSAC', 'ACEA / ILSAC', 'ACEA / ILSAC'),
        _specOem,
      ],
      after: L3('Бренд иккинчи ўринда туради.', 'Brend ikkinchi o‘rinda turadi.',
          'Бренд — на втором месте.'),
    ),
    ArtHeading(L3('Тўлиқ синтетик мой кимлар учун?',
        'To‘liq sintetik moy kimlar uchun?', 'Для кого полная синтетика?')),
    ArtCheck([
      L3('Янги автомобил эгалари.', 'Yangi avtomobil egalari.',
          'Владельцы новых авто.'),
      L3('Турбо двигателли автомобиллар.', 'Turbo dvigatelli avtomobillar.',
          'Автомобили с турбодвигателем.'),
      L3('Газ (LPG/CNG) ўрнатилган автомобиллар.',
          'Gaz (LPG/CNG) o‘rnatilgan avtomobillar.',
          'Автомобили с ГБО (LPG/CNG).'),
      L3('Узоқ сафар қиладиганлар.', 'Uzoq safar qiladiganlar.',
          'Те, кто ездит на дальние расстояния.'),
      L3('Иссиқ ва совуқ иқлимда кўп юрадиганлар.',
          'Issiq va sovuq iqlimda ko‘p yuradiganlar.',
          'Те, кто много ездит в жарком и холодном климате.'),
      L3('Двигателини узоқ йиллар яхши ҳолатда сақлашни истайдиганлар.',
          'Dvigatelini uzoq yillar yaxshi holatda saqlashni istaydiganlar.',
          'Те, кто хочет сохранить двигатель в хорошем состоянии на годы.'),
    ]),
    ArtHeading(L3('Минерал · Ярим · Тўлиқ — таққослаш',
        'Mineral · Yarim · To‘liq — taqqoslash',
        'Минеральное · Полусинтетика · Синтетика — сравнение')),
    ArtCompare(
      [
        L3('Кўрсаткич', 'Ko‘rsatkich', 'Показатель'),
        L3('Минерал', 'Mineral', 'Минеральное'),
        L3('Ярим', 'Yarim', 'Полусинт.'),
        L3('Тўлиқ', 'To‘liq', 'Синтетика'),
      ],
      [
        [
          L3('Нарх', 'Narx', 'Цена'),
          L3('⭐⭐⭐⭐⭐ арзон', '⭐⭐⭐⭐⭐ arzon', '⭐⭐⭐⭐⭐ дёшево'),
          L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
          L3('⭐⭐ қимматроқ', '⭐⭐ qimmatroq', '⭐⭐ дороже'),
        ],
        [
          L3('Двигател ҳимояси', 'Dvigatel himoyasi', 'Защита двигателя'),
          L3('⭐⭐', '⭐⭐', '⭐⭐'),
          L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
          L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
        ],
        [
          L3('Совуқда ишлаши', 'Sovuqda ishlashi', 'Работа на холоде'),
          L3('⭐⭐', '⭐⭐', '⭐⭐'),
          L3('⭐⭐⭐', '⭐⭐⭐', '⭐⭐⭐'),
          L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
        ],
        [
          L3('Иссиқда барқарорлик', 'Issiqda barqarorlik',
              'Стабильность в жару'),
          L3('⭐⭐', '⭐⭐', '⭐⭐'),
          L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
          L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
        ],
        [
          L3('Буғланиш', 'Bug‘lanish', 'Испарение'),
          L3('Юқорироқ', 'Yuqoriroq', 'Выше'),
          L3('Ўртача', 'O‘rtacha', 'Средне'),
          L3('Энг паст', 'Eng past', 'Самое низкое'),
        ],
        [
          L3('Хизмат муддати', 'Xizmat muddati', 'Срок службы'),
          L3('5–7 минг км', '5–7 ming km', '5–7 тыс. км'),
          L3('7–10 минг км', '7–10 ming km', '7–10 тыс. км'),
          L3('10–15 минг км*', '10–15 ming km*', '10–15 тыс. км*'),
        ],
        [
          L3('Газ (LPG)', 'Gaz (LPG)', 'Газ (LPG)'),
          L3('⭐⭐', '⭐⭐', '⭐⭐'),
          L3('⭐⭐⭐', '⭐⭐⭐', '⭐⭐⭐'),
          L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
        ],
        [
          L3('Турбо', 'Turbo', 'Турбо'),
          L3('⭐', '⭐', '⭐'),
          L3('⭐⭐', '⭐⭐', '⭐⭐'),
          L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
        ],
      ],
    ),
    ArtPara(L3(
      '* Фақат автомобил ишлаб чиқарувчиси белгилаган интервал ва эксплуатация шароитига мувофиқ.',
      '* Faqat avtomobil ishlab chiqaruvchisi belgilagan interval va ekspluatatsiya sharoitiga muvofiq.',
      '* Только в соответствии с интервалом, установленным производителем авто, и условиями эксплуатации.',
    )),
  ]),
};

/// Maqola bloklarini render qiluvchi widget.
class OilTypeArticleView extends StatelessWidget {
  const OilTypeArticleView({super.key, required this.article});

  final OilTypeArticle article;

  static const _ink = Color(0xFF1A2E1C);
  static const _muted = Color(0xFF6B7C6E);
  static const _green = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final lang = oilLangOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final b in article.blocks) _block(context, b, lang)],
    );
  }

  Widget _block(BuildContext context, OilArtBlock b, OilLang lang) {
    return switch (b) {
      ArtHero(:final text, :final color) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.t(lang),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.2,
            ),
          ),
        ),
      ArtLead(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.t(lang),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: _ink,
              height: 1.45,
            ),
          ),
        ),
      ArtPara(:final text, :final bold) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.t(lang),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: _ink,
              height: 1.45,
            ),
          ),
        ),
      ArtHeading(:final text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            text.t(lang),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: _green,
            ),
          ),
        ),
      ArtCheck(:final items) =>
        _list([for (final i in items) i.t(lang)], '✅'),
      ArtPros(:final items) => _list(
          [for (final i in items) i.t(lang)],
          '✔',
          markColor: const Color(0xFF2E7D32),
        ),
      ArtCons(:final items) => _list([for (final i in items) i.t(lang)], '❌'),
      ArtBrands(:final items) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in items)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3EF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDCE7DC)),
                  ),
                  child: Text(
                    s.t(lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ArtWhen(:final items, :final verdict) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5E5D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in items) _bullet(s.t(lang), '•'),
              if (verdict != null) ...[
                const SizedBox(height: 6),
                Text(
                  verdict.t(lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _green,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ArtKm(:final cards) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _kmCard(
                      cards[i].$1.t(lang),
                      cards[i].$2.t(lang),
                      cards[i].$3?.t(lang),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ArtSafe(:final title, :final body) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6EB),
            borderRadius: BorderRadius.circular(12),
            border: const Border(
              left: BorderSide(color: Color(0xFF2E7D32), width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.t(lang),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _green,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body.t(lang),
                style: const TextStyle(color: _ink, height: 1.4, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ArtGas(:final tag, :final paras, :final bullets, :final positive) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: positive ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: positive
                  ? const Color(0xFFA5D6A7)
                  : const Color(0xFFFFCC9E),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: positive
                      ? const Color(0xFF1B7A28)
                      : const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag.t(lang),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final p in paras) ...[
                Text(
                  p.t(lang),
                  style: const TextStyle(color: _ink, height: 1.4, fontSize: 13),
                ),
                const SizedBox(height: 6),
              ],
              for (final s in bullets) _bullet(s.t(lang), positive ? '✅' : '•'),
            ],
          ),
        ),
      ArtSae(:final pills) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in pills)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.$2.t(lang),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: _ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ArtSimple(:final label, :final lines, :final balance) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5E5D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.t(lang),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l.t(lang),
                    style: const TextStyle(color: _ink, height: 1.4),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                balance.t(lang),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _green,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ArtKeyTip(:final quote, :final before, :final specs, :final after) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('oil_key_tip_label'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: Colors.brown.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                quote.t(lang),
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  height: 1.4,
                ),
              ),
              if (before != null) ...[
                const SizedBox(height: 8),
                Text(before.t(lang),
                    style: const TextStyle(color: _ink, height: 1.4)),
              ],
              if (specs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in specs)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Text(
                          s.t(lang),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: _ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (after != null) ...[
                const SizedBox(height: 10),
                Text(
                  after.t(lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _ink,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ArtCompare(:final headers, :final rows) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 46,
              columnSpacing: 16,
              horizontalMargin: 10,
              headingRowColor:
                  const WidgetStatePropertyAll(Color(0xFFEEF6EF)),
              border: TableBorder.all(color: const Color(0xFFE0EBE0)),
              columns: [
                for (final h in headers)
                  DataColumn(
                    label: Text(
                      h.t(lang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: _ink,
                      ),
                    ),
                  ),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    cells: [
                      for (var i = 0; i < r.length; i++)
                        DataCell(
                          Text(
                            r[i].t(lang),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  i == 0 ? FontWeight.w700 : FontWeight.w500,
                              color: const Color(0xFF344736),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
    };
  }

  Widget _list(List<String> items, String mark, {Color? markColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in items) _bullet(s, mark, markColor: markColor)],
      ),
    );
  }

  Widget _bullet(String text, String mark, {Color? markColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              mark,
              style: TextStyle(fontSize: 13, color: markColor),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: _ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kmCard(String title, String value, String? note) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD5E5D6)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: _muted,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: _green,
              height: 1.2,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: _muted, height: 1.2),
            ),
          ],
        ],
      ),
    );
  }
}
