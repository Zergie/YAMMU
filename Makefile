ASSEMBLY_ID := urn:adsk.wipprod:dm.lineage:m1GM3AuVSsGAUndgrxP6jw
DIRECT_DRIVE_ID := urn:adsk.wipprod:dm.lineage:FxmAon5NSJe1PX8D-Y2Svg
RENDER_QUALITY := ShadedWithVisibleEdgesOnly
PYTHON := python3
SEND := FusionAddons/FusionHeadless/.venv/bin/python FusionAddons/FusionHeadless/send.py

.PHONY: all clean obj/STLs update_assembly
all: \
	FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py \
	update_assembly \
	obj/STLs \
	CAD/Assembly.zip \
	Manual/Assembly.pdf \
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
	mkdir -p obj && \
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
	$(SEND) --get /components --jmespath "result" --output $@

obj/components.printed.json: obj/components.json
	$(SEND) --file $< --match-with-files "STLs" --base-material "ABS Plastic (Voron Black)" --accent-material "ABS Plastic (Voron Red)" --output $@ && \
	mkdir -p obj/STLs && \
	$(SEND) --file $@ --outdir obj/STLs

obj/STLs: obj/components.printed.json
	$(SEND) --file $< --eval "'\n'.join(['rm $@/' + x.replace('.json', '.*') for x in [f for f in os.listdir('$@') if f.endswith('.json')] if not x in @.keys()])" \
		| sh && \
	$(SEND) --file $< --eval "'make ' + ' '.join(['$@/' + x['stl'] for x in @.values()])" \
		| sh

obj/STLs/%.stl: obj/STLs/%.json
	$(SEND) --file $< --jmespath "{component:component_id, body: bodies, format:'stl'}" \
		| $(SEND) --get /export --file - --output $@ && \
	$(SEND) --file $< --eval "f'stl_transform {@['rotation']} \"obj/STLs/{@['stl']}\" \"{@['path']}\" '" \
	    | sh

# obj/components.notprinted.json: obj/components.json
# 	$(SEND) --file $< \
# 		--jmespath "values(@)[?bodies[?material != 'ABS Plastic (Voron Black)' && material != 'ABS Plastic (Voron Red)']]" \
# 		--output $@


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

CAD/Assembly.zip: obj/Assembly.step
	mkdir -p CAD && \
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
	mkdir -p Manual && \
	soffice --headless --convert-to pdf:writer_pdf_Export $< --outdir Manual/


#### ##     ##    ###     ######   ########  ######  
 ##  ###   ###   ## ##   ##    ##  ##       ##    ## 
 ##  #### ####  ##   ##  ##        ##       ##       
 ##  ## ### ## ##     ## ##   #### ######    ######  
 ##  ##     ## ######### ##    ##  ##             ## 
 ##  ##     ## ##     ## ##    ##  ##       ##    ## 
#### ##     ## ##     ##  ######   ########  ######  

Images/render_1.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Tools", "view": "Render_1", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_ebay.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Electronincs Door", "view": "Render_ebay", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_heater.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Drawer", "view": "Render_heater", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_feeder.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "home", "isolate": "Direct Drive x4", "focalLength": 100, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_splitter.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "Render_Splitter", "isolate": "Direct Drive x4", "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/latch_lock.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "MotionStudy_Latch", "isolate": "Direct Drive x4", "hide": ["Filament Spools", "latch_a", "latch_b", "latch_mirror_a", "latch_mirror_b"], "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_cw2.png: obj/Assembly.json
	mkdir -p Images && \
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