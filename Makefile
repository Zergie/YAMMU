ASSEMBLY_ID := urn:adsk.wipprod:dm.lineage:m1GM3AuVSsGAUndgrxP6jw
DIRECT_DRIVE_ID := urn:adsk.wipprod:dm.lineage:FxmAon5NSJe1PX8D-Y2Svg
RENDER_QUALITY := ShadedWithVisibleEdgesOnly
PYTHON := python3
SEND := FusionAddons/FusionHeadless/.venv/bin/python FusionAddons/FusionHeadless/send.py

.PHONY: all clean
all: \
	FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py \
	obj/components.printed.json \
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
	$(SEND) --file $< \
		--jmespath "values(@)[?bodies[?material == 'ABS Plastic (Voron Black)' || material == 'ABS Plastic (Voron Red)']]" \
		--jmespath "[?!contains(name, 'Body')]" \
		--jmespath "[].{id:id, name: name, count: count, bodies: bodies[?material == 'ABS Plastic (Voron Black)' || material == 'ABS Plastic (Voron Red)']}" --plain \
		| $(SEND) --file - --match-with-files "STLs" --base-material "ABS Plastic (Voron Black)" --accent-material "ABS Plastic (Voron Red)" --output $@ && \
	$(SEND) --file $@ --outdir obj/



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
	$(SEND) --get /export/step --output $@

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
		--data '{"show": "all", "hide": "Tools", "view": "Render_1", "focalLength": 200, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_ebay.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Electronincs Door", "view": "Render_ebay", "focalLength": 200, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_heater.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Drawer", "view": "Render_heater", "focalLength": 200, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_feeder.png: obj/Assembly.json
	mkdir -p Images && \
	$(SEND) --get /document --data '{"open": "'"$(ASSEMBLY_ID)"'"}' && \
	$(SEND) --get /render \
		--data '{"view": "home", "isolate": "Direct Drive x4", "focalLength": 200, "quality": "$(RENDER_QUALITY)", "width": 400, "height": 400}' \
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