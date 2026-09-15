#!/usr/bin/env python3
"""Deterministically convert public setting facts to bounded camera-menu units.

Unknown/ambiguous controls are quarantined, never silently interpreted as zero.
No network, images, proprietary LUTs, source prose, or random preset expansion.
Source settings remain verbatim alongside the independently estimated mapping.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlsplit

MAPPING_VERSION = 1
BASES = {
    'classic chrome':'classicChrome', 'classic negative':'classicNegative', 'classic neg':'classicNegative',
    'eterna bleach bypass':'eternaBleachBypass', 'eterna/cinema':'eterna', 'eterna':'eterna',
    'pro neg std':'proNegStandard', 'pro neg hi':'proNegative', 'astia/soft':'astia', 'astia':'astia',
    'velvia/vivid':'velvia', 'velvia':'velvia', 'reala ace':'realaAce', 'provia/standard':'provia',
    'provia/std':'provia', 'provia':'provia', 'nostalgic neg':'nostalgicNegative', 'nostalgic negative':'nostalgicNegative',
    'monochrome':'monochrome', 'mono':'monochrome', 'acros':'acros', 'sepia':'sepia',
}
ALIASES = {
    'film simulation':'base', 'dynamic range':'dr', 'highlight':'highlight', 'highlights':'highlight', 'highlight tone':'highlight',
    'shadow':'shadow', 'shadows':'shadow', 'shadow tone':'shadow', 'colour':'color', 'color':'color',
    'white balance':'wb', 'wb':'wb', 'white balance shift':'shift', 'wb shift':'shift',
    'color chrome effect':'chrome', 'colour chrome effect':'chrome', 'col chr effect':'chrome',
    'color chrome fx blue':'blue', 'color chrome effect blue':'blue', 'color chrome blue':'blue', 'col chr blue':'blue',
    'colour chrome fx blue':'blue', 'grain effect':'grain', 'grain':'grain', 'grain size':'grainSize',
    'sharpness':'sharpness', 'sharpening':'sharpness', 'noise reduction':'nr', 'high iso nr':'nr',
    'high iso noise reduction':'nr', 'iso nr':'nr', 'iso n r':'nr', 'clarity':'clarity',
    'monochromatic color':'mono', 'monochromatic color (toning)':'mono', 'toning':'mono',
    'monochromatic colour':'mono', 'mono colour':'mono', 'mono color':'mono', 'b&w adjustment':'mono', 'd-range priority':'priority', 'd range priority':'priority',
    'iso':'iso', 'exposure compensation':'exposure', 'exposure comp':'exposure', 'exposure':'exposure', 'ev comp':'exposure',
}

def clean(value):
    value = unicodedata.normalize('NFKC', value)
    value = value.translate(str.maketrans({c:'-' for c in '−‐‑‒–—'}))
    return re.sub(r'\s+', ' ', value).strip()

def key(value):
    return re.sub(r'\s+', ' ', clean(value).lower().replace('.', '')).strip()

def scalar(value, label, low, high):
    value = clean(value)
    # Parentheses may explain the same scalar, e.g. '-1 (Medium-Soft)', but
    # alternatives/ranges need review rather than choosing an arbitrary value.
    match = re.fullmatch(r'([+-]?\d+(?:\.\d+)?)\s*(?:\(([^()]*)\))?\*?', value)
    if not match or (match[2] and re.search(r'\d|\bor\b', match[2], re.I)):
        raise ValueError(f'{label}: ambiguous scalar {value}')
    number = float(match[1])
    if not low <= number <= high:
        raise ValueError(f'{label}: out of range {number}')
    return number

def categorical(value, label, notes):
    value = clean(value)
    if key(value) in ('off/na', 'off or n/a', 'n/a (x-trans iii) or off (x-t3/x-t30)'):
        notes.append(f'{label}: the source marks the control Off or unavailable; the adaptation disables it.')
        return 0
    match = re.fullmatch(r'(Off|None|Weak|Strong)(?:\s*\(([^()]*)\))?', value, re.I)
    if not match:
        raise ValueError(f'{label}: ambiguous strength {value}')
    if match[2]:
        # A source may explicitly give its first setting followed by a camera
        # generation alternative. Retain the alternate, label the primary.
        notes.append(f'{label}: uses the first published setting ({match[1]}); any parenthetical alternative is retained in source settings.')
    return {'off':0,'none':0,'weak':1,'strong':2}[match[1].lower()]

def canonical_settings(raw):
    result = {}
    for name, value in raw.items():
        canonical = ALIASES.get(key(name))
        if canonical is None:
            raise ValueError(f'Unknown setting key: {name}')
        # Earlier paragraph collector versions missed inline Grain/Toning.
        # Split only explicit labeled fields; original source facts stay intact.
        parts = re.split(r'\s+(Grain|Monochromatic Color\s*\(Toning\))\s*:\s*', clean(value), flags=re.I)
        if canonical in result and result[canonical] != parts[0]:
            raise ValueError(f'Contradictory {canonical} entries')
        result[canonical] = parts[0].strip()
        for i in range(1, len(parts), 2):
            extra = 'grain' if parts[i].lower() == 'grain' else 'mono'
            if extra in result and result[extra] != parts[i + 1]:
                raise ValueError(f'Contradictory embedded {extra}')
            result[extra] = parts[i + 1].strip()
    return result

def parse_base(value, notes):
    normalized = key(value)
    if normalized in BASES:
        return BASES[normalized]
    mono = re.fullmatch(r'(acros|monochrome|mono)\s*(?:\+\s*(ye?|r|g)|\s+(yellow|red|green)\s+filter)', normalized)
    if mono:
        base = 'acros' if mono[1] == 'acros' else 'monochrome'
        channel = mono[2] or mono[3]
        return base + {'y':'Yellow','ye':'Yellow','r':'Red','g':'Green','yellow':'Yellow','red':'Red','green':'Green'}[channel]
    if re.fullmatch(r'(acros|monochrome)\s*\((?:including|or)?[\w\s+,]*\)', normalized):
        notes.append('The source offers optional monochrome filters. This entry uses its first, unfiltered mode, not extra generated variants.')
        return normalized.split('(')[0].strip()
    raise ValueError(f'Unsupported or ambiguous film simulation: {value}')

def white_balance(value, shift, notes):
    value = clean(value)
    # Kelvin may be published without K. A 4-digit leading value is unambiguous.
    kelvin = re.match(r'^(\d{4,5})\s*K?\b', value, re.I)
    mode_text = value.split(',')[0].strip().lower()
    if kelvin:
        mode, temperature = 'colorTemperature', float(kelvin[1])
        if not 2500 <= temperature <= 10000:
            raise ValueError('White balance Kelvin outside supported bounds')
    else:
        temperature = 5600
        modes = {'auto':'auto', 'auto white priority':'whitePriority', 'auto (white priority)':'whitePriority',
                 'white priority':'whitePriority', 'auto ambience priority':'ambiencePriority', 'ambience priority':'ambiencePriority',
                 'auto (ambience priority)':'ambiencePriority', 'daylight':'daylight', 'daylight/fine':'daylight', 'fine':'daylight', 'awb':'auto', 'shade':'shade',
                 'cloudy/shade':'shade', 'incandescent':'incandescent', 'underwater':'underwater', 'tungsten':'incandescent'}
        fluor = re.fullmatch(r'fluorescent ([123])(?:\s*\([^)]*\))?', mode_text)
        mode = f'fluorescent{fluor[1]}' if fluor else modes.get(mode_text)
        if mode is None:
            raise ValueError(f'Unsupported white balance mode: {mode_text}')
    shifts = clean(shift or value)
    red = re.findall(r'([+-]?\d+(?:\.\d+)?)\s*Red\b', shifts, flags=re.I)
    blue = re.findall(r'([+-]?\d+(?:\.\d+)?)\s*Blue\b', shifts, flags=re.I)
    if not red and not blue and ',' not in value and not shift:
        notes.append('No white-balance fine shift is published; the adaptation uses a neutral 0/0 shift.')
        red, blue = ['0'], ['0']
    if len(red) != 1 or len(blue) != 1:
        raise ValueError(f'Ambiguous white balance shifts: {value}')
    return mode, temperature, scalar(red[0], 'Red WB', -9, 9), scalar(blue[0], 'Blue WB', -9, 9)

def normalize(record):
    host = urlsplit(record['url']).netloc
    publisher = {'film.recipes':'filmRecipes','fujixweekly.com':'fujiXWeekly'}.get(host)
    if publisher is None or urlsplit(record['url']).scheme != 'https':
        raise ValueError('Source not allowlisted')
    values = canonical_settings(record['settings'])
    notes = []
    base = parse_base(values['base'], notes)
    mono = base.startswith(('acros','monochrome')) or base == 'sepia'
    if 'priority' in values and key(values['priority']) not in ('off','dr-p off'):
        raise ValueError('Dynamic Range Priority needs a separate supported mapping')
    dr_value = key(values.get('dr',''))
    dr = {'dr100':100,'dr200':200,'dr400':400,'auto':0,'dr-auto':0,'dr auto':0}.get(dr_value)
    if dr is None:
        raise ValueError(f'Ambiguous dynamic range: {dr_value}')
    h = scalar(values['highlight'], 'Highlight', -2, 4)
    s = scalar(values['shadow'], 'Shadow', -2, 4)
    color = 0 if mono else scalar(values['color'], 'Color', -4, 4)
    mode, kelvin, red, blue = white_balance(values['wb'], values.get('shift'), notes)
    if host == 'film.recipes' and not mono and ('chrome' not in values or 'blue' not in values):
        raise ValueError('Incomplete abbreviated table: Color Chrome fields need re-collection')
    chrome = categorical(values.get('chrome','Off'), 'Color Chrome', notes)
    fx = categorical(values.get('blue','Off'), 'FX Blue', notes)
    missing = [label for name,label in [('chrome','Color Chrome'),('blue','FX Blue'),('grain','grain'),('clarity','clarity'),('nr','additional noise reduction'),('sharpness','sharpening')]
               if name not in values]
    if missing:
        notes.append('Controls absent from the source are disabled: ' + ', '.join(missing) + '. This does not infer support on the original camera.')
    raw_grain = values.get('grain','Off')
    grain_parts = [p.strip() for p in raw_grain.split(',')]
    grain = categorical(grain_parts[0], 'Grain', notes)
    size = values.get('grainSize', grain_parts[1] if len(grain_parts) == 2 else 'Small')
    if key(size) not in ('small','large') or len(grain_parts)>2:
        raise ValueError(f'Unsupported grain size: {raw_grain}')
    if grain and 'grainSize' not in values and len(grain_parts)==1:
        notes.append('Grain size is not specified by the source; Small is the explicit adaptation default.')
    sharpness = scalar(values.get('sharpness','0'), 'Sharpness', -4, 4)
    nr = scalar(values.get('nr','-4'), 'Noise reduction', -4, 4)
    clarity = scalar(values.get('clarity','0'), 'Clarity', -5, 5)
    wc, mg = 0, 0
    if 'mono' in values:
        toning = clean(values['mono'])
        axes = re.search(r'WC\s*:?\s*([+-]?\d+)\s*[, &]*\s*MG\s*:?\s*([+-]?\d+)', toning, re.I)
        reverse = re.search(r'([+-]?\d+)\s*WC\s*[, &]*\s*([+-]?\d+)\s*MG', toning,re.I)
        if axes or reverse:
            found=axes or reverse
            wc,mg=scalar(found[1],'WC',-18,18),scalar(found[2],'MG',-18,18)
        elif key(toning) not in ('off','0','off (wc 0 & mg 0)'):
            raise ValueError(f'Unmapped monochrome toning axis: {toning}')
    indexes = record['indexes']
    generations = sorted(set(re.search(r'x-trans-([iv]+)-', u)[1].upper() for u in indexes if re.search(r'x-trans-([iv]+)-',u)), key=lambda g:len(g))
    scope = 'X-Trans ' + ' / '.join(generations) + ' source index' if generations else 'Published primary camera settings'
    if host == 'film.recipes':
        notes.append('Uses the primary table values; camera-specific alternatives remain visible in the source. The phone is not treated as an X-Trans sensor.')
    controls = dict(filmBase=base,dynamicRange=dr,highlight=h,shadow=s,color=color,
                    whiteBalanceMode=mode,kelvin=kelvin,redShift=red,blueShift=blue,
                    colorChrome=chrome,fxBlue=fx,sharpness=sharpness,noiseReduction=nr,clarity=clarity,
                    grain=grain,grainSize=0 if key(size)=='small' else 1,
                    monochromaticWarmCool=wc,monochromaticGreenMagenta=mg)
    slug = re.sub(r'[^a-z0-9]+','-',unicodedata.normalize('NFKD',record['name']).encode('ascii','ignore').decode().lower()).strip('-')[:70]
    suffix=hashlib.sha256(record['url'].encode()).hexdigest()[:12]
    identifier=f'source-{publisher.lower()}-{slug}-{suffix}'
    return dict(id=identifier,name=record['name'].strip(),source=dict(publisher=publisher,originalName=record['name'].strip(),
            url=record['url'],cameraScope=scope,retrievedOn=record['retrievedOn'],sourceSHA256=record['sourceSHA256'],
            settings=record['settings'],limitations=notes,mappingVersion=MAPPING_VERSION),controls=controls)

def build(data):
    accepted=[]
    rejected=list(data.get('failures',[]))
    seen=set()
    for raw in data['records']:
        try:
            item=normalize(raw)
            if item['source']['url'] in seen:
                raise ValueError('Duplicate source URL')
            seen.add(item['source']['url'])
            accepted.append(item)
        except (ValueError,KeyError,TypeError) as error:
            rejected.append(dict(url=raw['url'],reason=str(error)))
    counts=Counter(x['name'].casefold() for x in accepted)
    for item in accepted:
        # All source names get a compact source badge in the display name,
        # preventing collisions with authored Filmy looks. Repeated names
        # across generations add the publication year and a stable URL hash.
        badge='FXW' if item['source']['publisher']=='fujiXWeekly' else 'FR'
        item['name']+=f' / {badge}'
        if counts[item['source']['originalName'].casefold()]>1:
            year=re.search(r'/([12]\d{3})/',item['source']['url'])[1]
            item['name']+=f' {year} {item["id"][-4:]}'
    accepted.sort(key=lambda r:(r['source']['publisher'],r['name'].casefold(),r['id']))
    fingerprints=Counter(json.dumps(x['controls'],sort_keys=True) for x in accepted)
    report=dict(schemaVersion=1,candidates=data.get('candidateCount',len(data['records'])),
                accepted=len(accepted),publisherCounts=dict(Counter(r['source']['publisher'] for r in accepted)),
                distinctControlSets=len(fingerprints),sameControlGroups=[
                    [r['id'] for r in accepted if json.dumps(r['controls'],sort_keys=True)==fp]
                    for fp,n in fingerprints.items() if n>1],rejected=rejected,
                mappingVersion=MAPPING_VERSION,calibration='Not calibrated to camera hardware; source settings are not pixel-match evidence.')
    return {'schemaVersion':1,'records':accepted},report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('staging',type=Path)
    parser.add_argument('--output',type=Path,default=Path('FilmyCamera/Resources/RecipeCatalog.json'))
    parser.add_argument('--report',type=Path,default=Path('docs/recipe-catalog-audit.json'))
    args=parser.parse_args()
    catalog,report=build(json.loads(args.staging.read_text()))
    for path,data in [(args.output,catalog),(args.report,report)]:
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('rejected','sameControlGroups')},indent=2))
    print('Rejected:',len(report['rejected']))

if __name__=='__main__':
    main()
