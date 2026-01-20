ASSEMBLY_ID := urn:adsk.wipprod:dm.lineage:m1GM3AuVSsGAUndgrxP6jw
DIRECT_DRIVE_ID := urn:adsk.wipprod:dm.lineage:FxmAon5NSJe1PX8D-Y2Svg
RENDER_QUALITY := ShadedWithVisibleEdgesOnly
PYTHON := python3
VPYTHON := FusionAddons/FusionHeadless/.venv/bin/python3
SEND := $(VPYTHON) FusionAddons/FusionHeadless/send.py

.PHONY: all images clean obj/STLs update_assembly
all: \
	FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py \
	update_assembly \
	obj/STLs \
	CAD/Assembly.f3d \
	CAD/Assembly.zip \
	Manual/Assembly.pdf

images: \
	Images/render_1.png \
	Images/render_ebay.png \
	Images/render_heater.png \
	Images/render_feeder.png \
	Images/render_splitter.png \
	Images/latch_lock.png \
	Images/render_cw2.png


 ######  ######## ######## ##     ## ########
##    ## ##          ##    ##     ## ##     ##
##       ##          ##    ##     ## ##     ##
 ######  ######      ##    ##     ## ########
      ## ##          ##    ##     ## ##
##    ## ##          ##    ##     ## ##
 ######  ########    ##     #######  ##

FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py: FusionAddons/FusionHeadless/requirements.txt FusionAddons/FusionHeadless/Makefile
	cd FusionAddons/FusionHeadless && make && cd ../.. && touch $@

obj/Assembly.json:
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /files --data '{"id": "'"$(ASSEMBLY_ID)"'"}' --jmespath "result" --output $@

update_assembly:
	make -B obj/Assembly.json


 ######  ######## ##        ######
##    ##    ##    ##       ##    ##
##          ##    ##       ##
 ######     ##    ##        ######
      ##    ##    ##             ##
##    ##    ##    ##       ##    ##
 ######     ##    ########  ######

obj/components.json: obj/Assembly.json
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /components --jmespath "result" --timeout 120 --output $@

obj/components.printed.json: obj/components.json
	$(SEND) --file $< --match-with-files "STLs" --base-material "ABS Plastic (Voron Black)" --accent-material "ABS Plastic (Voron Red)" --output $@ && \
	mkdir -p obj/STLs && \
	$(SEND) --file $@ --outdir obj/STLs

obj/STLs: obj/components.printed.json
	$(SEND) --file $< --eval "'\n'.join(['rm $@/' + x.replace('.json', '.*') for x in [f for f in os.listdir('$@') if f.endswith('.json')] if not x in @.keys()])" \
		| sh && \
	$(SEND) --file $< --eval "'make ' + ' '.join([f'$@/{x['id']}.stl' for x in @.values()])" \
		| sh

obj/STLs/%.stl: obj/STLs/%.json
	rm -f $(basename $@).1.stl && \
	rm -f $@ && \
	$(SEND) --file $< --jmespath "{component:component_id, body: bodies, format:'stl'}" \
		| $(SEND) --get /export --file - --output $@ && \
	$(SEND) --file $< --eval "f'stl_transform {@['rotation']} \"$@\" \"$(basename $@).1.stl\" '" | \
		sh && \
	stl_bbox $(basename $@).1.stl | \
		grep -oE '[-]?[0-9]+(\.[0-9]+)?' | \
		paste -sd, - | \
		sed 's/^/{"bbox":[/' | \
		sed 's/$$/]}/' | \
		$(SEND) --file $< --file - --eval "@.update({'transform': f'-tx {-(@['bbox'][0]+@['bbox'][3])/2} -ty {-(@['bbox'][1]+@['bbox'][4])/2} -tz {-@['bbox'][2]}'})" | \
		$(SEND) --file - --eval "f'stl_transform {@['transform']} \"$(basename $@).1.stl\" \"{@['path']}\"'" | \
		sh && \
	rm -f $(basename $@).1.stl


########   #######  ##     ##
##     ## ##     ## ###   ###
##     ## ##     ## #### ####
########  ##     ## ## ### ##
##     ## ##     ## ##     ##
##     ## ##     ## ##     ##
########   #######  ##     ##

BOM.md: obj/bom.json
	$(VPYTHON) -c "\
import json;\
data = json.load(open('$<', 'r', encoding='utf-8'));\
print('| Type                   | Count |');\
print('| ---------------------- | ----- |');\
print('\\n'.join(['| ' + k.ljust(22) + ' | ' +  str(v).rjust(5) + ' |' for k, v in data.items()]))\
" > $@

obj/bom.json: obj/bom.categorized.json
	$(SEND) --file $< \
		--eval "{k: sum(x['count'] for x in @ if x['type'] == k) for k in sorted(set(x['type'] for x in @ if x['type'] != None))}" \
		--output $@

obj/bom.categorized.json: obj/components.notprinted.json
	$(SEND) --file $< \
		--eval "[x.update({ \
			'type': 'Drop-In T-Nut'         if 'Drop-In T-Nut'    in x['name'] \
				else 'Hammerhead T-Nut'     if 'Hammerhead T-Nut' in x['name'] \
				else 'Extrusion'            if 'Extrusion'        in x['name'] \
				else 'Threaded Rod'         if 'Threaded Rod'     in x['name'] \
				else 'Magnet'               if 'Magnet'           in x['name'] \
				else 'Hex Nut'              if 'Hex Nut'          in x['name'] \
				else 'Rubber Foot'          if 'Rubber Foot'      in x['name'] \
				else 'DIN Rail'             if 'DIN Rail'         in x['name'] \
				else 'XLG 150 PSU'          if 'XLG 150 PSU'      in x['name'] \
				else 'Wago 221-415'         if 'Wago 221-415'     in x['name'] \
				else '608-2RS Ballbearing'  if '608-2RS'          in x['name'] \
				else '623-2RS Ballbearing'  if '623-2RS'          in x['name'] \
				else 'MR825 Ballbearing'    if 'MR825'            in x['name'] \
				else 'MR85ZZ Ballbearing'   if 'MR85ZZ'           in x['name'] \
				else 'MH37-3525 BLDC Motor' if 'MH37-3525'        in x['name'] \
				else 'Washer DIN 125-2'     if 'DIN 125-2'        in x['name'] \
				else 'Steel Ball'           if 'Steel Ball'       in x['name'] \
				else 'Bondtech Gear'        if 'Drive Gear'       in x['name'] or 'Moving Gear Assembly' in x['name'] \
				else 'Heatset Insert'       if 'Threaded Insert'  in x['name'] or 'Heatset' in x['name'] \
				else 'VHB Tape'             if 'VHB'              in x['name'] \
				else 'BHCS' if 'BHCS' in x['name'] or 'ISO 7380'  in x['name'] \
				else 'SHCS' if 'SHCS' in x['name'] or 'DIN 912'   in x['name'] \
				else 'FHCS' if 'FHCS' in x['name'] or 'DIN 7991'  in x['name'] \
				else 'PHCS' if 'PHCS' in x['name'] or 'B18.6.5M'  in x['name'] \
				else None, \
			'size': x.search('name', r'M\d+(\s*x\s*\d+(\.\d+)?)?(\s*x\s*\d+(\.\d+)?)?') or \
					x.search('name', r'\d+\.\d+') or \
					x.search('name', r'\d+x\d+') or \
					x.search('name', r'\d+\s*mm') \
		}) for x in @]" \
		--eval "[x.update({'size': x['size'].replace(' ', '') if x['size'] else None}) for x in @]" \
		--eval "[x.update({'size': x.sub('size', r'x\d(\.\d+)?x', r'x')}) for x in @]" \
		--eval "[x.update({'type': x['type'] + (' ' + x['size'] if x['size'] else '') if x['type'] else None}) for x in @]" \
		--output $@

obj/components.notprinted.json: obj/components.json
	$(SEND) --file $< \
		--jmespath "values(@)[?bodies[?material != 'ABS Plastic (Voron Black)' && material != 'ABS Plastic (Voron Red)']].{name: name, material: material, count: count}" \
		--output $@


 ######     ###    ########
##    ##   ## ##   ##     ##
##        ##   ##  ##     ##
##       ##     ## ##     ##
##       ######### ##     ##
##    ## ##     ## ##     ##
 ######  ##     ## ########

obj/Assembly.step: obj/Assembly.json
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /export --data '{"format": "step"}' --output $@

CAD/Assembly.f3d: obj/Assembly.json
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /export --data '{"format": "f3d"}' --output $@

CAD/Assembly.zip: obj/Assembly.step
	mkdir -p $(dir $@) && \
	cd obj && \
	zip Assembly.zip Assembly.step && \
	cd .. && \
	mv --force obj/Assembly.zip $@


##     ##    ###    ##    ## ##     ##    ###    ##
###   ###   ## ##   ###   ## ##     ##   ## ##   ##
#### ####  ##   ##  ####  ## ##     ##  ##   ##  ##
## ### ## ##     ## ## ## ## ##     ## ##     ## ##
##     ## ######### ##  #### ##     ## ######### ##
##     ## ##     ## ##   ### ##     ## ##     ## ##
##     ## ##     ## ##    ##  #######  ##     ## ########

Manual/Assembly.pdf: Manual/Assembly.odp
	mkdir -p $(dir $@) && \
	soffice --headless --convert-to pdf:writer_pdf_Export $< --outdir Manual/


#### ##     ##    ###     ######   ########  ######
 ##  ###   ###   ## ##   ##    ##  ##       ##    ##
 ##  #### ####  ##   ##  ##        ##       ##
 ##  ## ### ## ##     ## ##   #### ######    ######
 ##  ##     ## ######### ##    ##  ##             ##
 ##  ##     ## ##     ## ##    ##  ##       ##    ##
#### ##     ## ##     ##  ######   ########  ######

Images/render_1.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Tools", "view": "Render_1", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@ && \
	convert $@ -fuzz 10% -trim +repage $@ && \
	convert $@ -bordercolor white -border 200 $@ && \
	convert $@ -gravity center -crop 400x400+0+0 +repage $@

Images/render_ebay.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Electronincs Door", "view": "Render_ebay", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_heater.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Drawer", "view": "Render_heater", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_feeder.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "home", "isolate": "Direct Drive x4", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_splitter.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "Render_Splitter", "isolate": "Direct Drive x4", "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/latch_lock.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "MotionStudy_Latch", "isolate": "Direct Drive x4", "hide": ["Filament Spools", "latch_a", "latch_b", "latch_mirror_a", "latch_mirror_b"], "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_cw2.png: obj/Assembly.json
	mkdir -p $(dir $@) && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "home", "isolate": "Stealthburner_CW2_Filament_Sensor_ECAS", "exposure": 8.2, "focalLength": 200, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@


 ######  ##       ########    ###    ##    ##
##    ## ##       ##         ## ##   ###   ##
##       ##       ##        ##   ##  ####  ##
##       ##       ######   ##     ## ## ## ##
##       ##       ##       ######### ##  ####
##    ## ##       ##       ##     ## ##   ###
 ######  ######## ######## ##     ## ##    ##

clean:
	cd FusionAddons/FusionHeadless && make clean && cd ../..
	rm -rf obj