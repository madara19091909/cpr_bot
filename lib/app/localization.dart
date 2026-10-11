import 'package:flutter/material.dart';

/// Lightweight Flutter localization (ar default, en). Keys missing in a
/// language fall back to English, never to a blank string.
class AppStrings {
  AppStrings(this.locale);
  final Locale locale;

  static AppStrings of(BuildContext c) =>
      Localizations.of<AppStrings>(c, AppStrings)!;

  static const delegate = _Delegate();
  static const supported = [Locale('ar'), Locale('en')];

  String t(String key) =>
      _all[locale.languageCode]?[key] ?? _all['en']![key] ?? key;

  static const _all = <String, Map<String, String>>{
    'en': {
      'app': 'MC Manger',
      'library': 'World library',
      'pick': 'Choose folder (SAF)',
      'scanCommon': 'Scan common locations',
      'scanImports': 'Scan imported copies',
      'noWorlds': 'No worlds found. Pick the minecraftWorlds folder (or one world) with the folder picker.',
      'copying': 'Copying a read-only working copy…',
      'size': 'Size',
      'files': 'Files',
      'modified': 'Last modified',
      'unknown': 'Unknown',
      'yes': 'Yes',
      'no': 'No',
      'metadata': 'level.dat metadata',
      'levelDatEditor': 'Edit level.dat',
      'editLevelDat': 'Edit level.dat',
      'saveChanges': 'Save changes',
      'saving': 'Saving…',
      'exportMcworld': 'Export .mcworld for Minecraft',
      'levelName': 'World name',
      'gameType': 'Game mode (raw value)',
      'difficulty': 'Difficulty (raw value)',
      'spawn': 'World spawn',
      'seed': 'Seed (raw value)',
      'lastVersion': 'Last opened with',
      'otherKeys': 'Other keys (preserved, not interpreted)',
      'backups': 'Backups',
      'createBackup': 'Create backup',
      'verify': 'Verify',
      'restore': 'Restore to new folder',
      'delete': 'Delete',
      'confirmDelete': 'Delete this backup permanently?',
      'cancel': 'Cancel',
      'ok': 'OK',
      'unverifiedNote': 'Unverified snapshot: the app cannot tell whether Minecraft was writing. Close the game before backing up.',
      'incomplete': 'Incomplete backup',
      'language': 'Language',
      'errors': 'Errors',
      'hasLevelDat': 'level.dat present',
      'hasDb': 'db folder present',
      'readable': 'level.dat readable',
      'parseFailed': 'level.dat could not be parsed',
      'database': 'Database explorer',
      'dbSummary': 'Records',
      'search': 'Search (key hex or text)',
      'allFamilies': 'All',
      'valueSize': 'Value size',
      'copyHex': 'Copy key (hex)',
      'rawView': 'Raw (hex)',
      'parsedView': 'Parsed NBT',
      'noParse': 'Value is not valid NBT (shown raw only).',
      'dbCorrupt': 'Corruption / read problems (some records may be missing)',
      'dbWarnings': 'Warnings',
      'patternNote': 'Key families are guessed from the key pattern only and are unverified for 1.26.x.',
      'players': 'Player summary',
      'readOnly': 'Read-only: nothing is ever written to the database.',
      'map': 'World map',
      'render': 'Render',
      'centerX': 'Center X',
      'centerZ': 'Center Z',
      'mapEmpty': 'No sub-chunk records found for this dimension.',
      'chunksDrawn': 'Chunks drawn',
      'unmapped': 'Blocks with approximate colour',
      'mapNote': 'Top-down surface view from SubChunkPrefix records. Colours are approximate; layout decoding is unverified for 1.26.x. Window is capped at 128x128 chunks.',
      'filterName': 'Filter by file name',
      'computeHash': 'SHA-256',
      'preview': 'Preview',
      'exportCopy': 'Export copy',
      'exported': 'Exported to',
      'sensitiveWarn': 'This file is part of the world database and may contain private player data. Export anyway?',
      'dbNotice': 'Database inspection is not implemented yet.',
    },
    'ar': {
      'app': 'MC Manger',
      'library': 'مكتبة العوالم',
      'pick': 'اختيار مجلد (SAF)',
      'scanCommon': 'فحص المواقع الشائعة',
      'scanImports': 'فحص النسخ المستوردة',
      'noWorlds': 'لم يتم العثور على عوالم. اختر مجلد minecraftWorlds (أو عالماً واحداً) من أداة اختيار المجلد.',
      'copying': 'جارٍ نسخ نسخة عمل للقراءة فقط…',
      'size': 'الحجم',
      'files': 'الملفات',
      'modified': 'آخر تعديل',
      'unknown': 'غير معروف',
      'yes': 'نعم',
      'no': 'لا',
      'metadata': 'بيانات level.dat',
      'levelDatEditor': 'محرر level.dat',
      'editLevelDat': 'تعديل level.dat',
      'saveChanges': 'حفظ التعديلات',
      'saving': 'جارٍ الحفظ…',
      'exportMcworld': 'تصدير .mcworld إلى Minecraft',
      'levelName': 'اسم العالم',
      'gameType': 'نمط اللعب (القيمة الخام)',
      'difficulty': 'الصعوبة (القيمة الخام)',
      'spawn': 'نقطة ظهور العالم',
      'seed': 'البذرة (القيمة الخام)',
      'lastVersion': 'آخر إصدار فتح العالم',
      'otherKeys': 'مفاتيح أخرى (محفوظة وغير مفسَّرة)',
      'backups': 'النسخ الاحتياطية',
      'createBackup': 'إنشاء نسخة احتياطية',
      'verify': 'تحقق',
      'restore': 'استعادة إلى مجلد جديد',
      'delete': 'حذف',
      'confirmDelete': 'حذف هذه النسخة نهائياً؟',
      'cancel': 'إلغاء',
      'ok': 'موافق',
      'unverifiedNote': 'لقطة غير مؤكدة: لا يستطيع التطبيق معرفة ما إذا كانت اللعبة تكتب. أغلق اللعبة قبل النسخ.',
      'incomplete': 'نسخة غير مكتملة',
      'language': 'اللغة',
      'errors': 'الأخطاء',
      'hasLevelDat': 'ملف level.dat موجود',
      'hasDb': 'مجلد db موجود',
      'readable': 'ملف level.dat قابل للقراءة',
      'parseFailed': 'تعذر تحليل ملف level.dat',
      'database': 'مستكشف قاعدة البيانات',
      'dbSummary': 'السجلات',
      'search': 'بحث (مفتاح hex أو نص)',
      'allFamilies': 'الكل',
      'valueSize': 'حجم القيمة',
      'copyHex': 'نسخ المفتاح (hex)',
      'rawView': 'خام (hex)',
      'parsedView': 'NBT محلَّل',
      'noParse': 'القيمة ليست NBT صالحاً (تُعرض خام فقط).',
      'dbCorrupt': 'مشاكل تلف/قراءة (قد تكون بعض السجلات مفقودة)',
      'dbWarnings': 'تحذيرات',
      'patternNote': 'تصنيف المفاتيح تخميني من نمط المفتاح فقط وغير مُتحقَّق منه لإصدار 1.26.',
      'players': 'ملخص اللاعب',
      'readOnly': 'للقراءة فقط: لا يُكتب أي شيء في قاعدة البيانات.',
      'map': 'خريطة العالم',
      'render': 'ارسم',
      'centerX': 'المركز X',
      'centerZ': 'المركز Z',
      'mapEmpty': 'لا توجد سجلات sub-chunk لهذا البُعد.',
      'chunksDrawn': 'الـchunks المرسومة',
      'unmapped': 'بلوكات بلون تقريبي',
      'mapNote': 'منظر علوي للسطح من سجلات SubChunkPrefix. الألوان تقريبية وفك البنية غير مُتحقَّق منه لإصدار 1.26. النافذة محدودة بـ 128×128 chunk.',
      'filterName': 'تصفية باسم الملف',
      'computeHash': 'SHA-256',
      'preview': 'معاينة',
      'exportCopy': 'تصدير نسخة',
      'exported': 'تم التصدير إلى',
      'sensitiveWarn': 'هذا الملف جزء من قاعدة بيانات العالم وقد يحتوي بيانات خاصة باللاعبين. هل تريد التصدير؟',
      'dbNotice': 'فحص قاعدة البيانات غير مُنفَّذ بعد.',
    },
  };
}

class _Delegate extends LocalizationsDelegate<AppStrings> {
  const _Delegate();
  @override
  bool isSupported(Locale l) => const ['ar', 'en'].contains(l.languageCode);
  @override
  Future<AppStrings> load(Locale l) async => AppStrings(l);
  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

/// Paths, hashes and identifiers must stay LTR even inside Arabic UI.
class LtrText extends StatelessWidget {
  const LtrText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(text, style: style, textAlign: TextAlign.left),
      );
}
