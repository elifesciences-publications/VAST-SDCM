/*
Process_VAST v1.1
2018-03-30
Copyright (c) 30/03/2018 Jason J Early
The University of Edinburgh

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

var filesSorted, timeSorted, trigOut, trigIn, well, fishNumW, orient, xPos, angle, lineCount, stackNum, zMIPIn, stitchOutput, images, prefix, noStitch, type, BF,stitchBF, splitChannel, OverL, GX, mipInput, RegTh,zStitch,meanX,meanY, count, imProp;
setBatchMode(true);

#@ File(label = "Input directory containing z-Stacks:", style = "directory") input
#@ File(label = "Input directory containing z-MIPs:", style = "directory") zMIPIn
#@ File(label = "Output directory for concatenated files:", style = "directory") concatOutput
#@ File(label = "Output directory for stitched files:", style = "directory") stitchOutput
#@ String(label = "zMIP prefix:", value = "zMIP_") zMipPrefix
#@ String(label = "File suffix:", value = ".czi") suffix
#@ File(label = "Select VAST output CSV file:", style = "open") file
#@ String(label = "Stitch using:", choices={"zMIP", "zStack","neither"}, style="radioButtonHorizontal") type
#@ Boolean(label = "Are brightfield images present?", value = false) BF
#@ Boolean(label = "Stitch BF file seperately?", description = "i.e. if there z-stacks have different number of slices.", value = false) splitChannel
#@ Boolean(label = "Stitch brightfield images?", value = false) stitchBF

macro "Process_VAST"{
	input = input+File.separator;
	zMIPIn = zMIPIn+File.separator;
	concatOutput = concatOutput+File.separator;
	stitchOutput = stitchOutput+File.separator;
	
	if(type=="neither") noStitch = true;
	else noStitch = false;
	
	stackNum = 2;
	lineCount = 0;
	if(BF == true) stackNum = stackNum*2;
	zMipPrefix =  "zMIP_";
	mipInput = concatOutput;
	//Stitching Preferences
	if(noStitch == false){
		Dialog.create("File type");
		Dialog.addNumber("% Tile Overlap:", 10.37); //11.67
		Dialog.addNumber("X tiles (Y assumed 1)", 5);
		Dialog.addNumber("Registration Threshold", 0.6);
	//	Dialog.addCheckbox("Stitch Z-Stacks?", false);
		Dialog.addString("Default tile positions:", "0,0:709,4.8:1414,10.9:2119,17.1:2820,22.7", 50);
		Dialog.show();
		OverL = Dialog.getNumber();
		GX = Dialog.getNumber();
		RegTh = Dialog.getNumber();
	//	zStitch = Dialog.getCheckbox();
		xyTemp = Dialog.getString();
	xyTemp = split(xyTemp, ":");
	listX = newArray((xyTemp.length));
	listY = newArray((xyTemp.length));
	for(i=0; i<xyTemp.length; i++){
		tempArray = split(xyTemp[i], ",");
		listX[i] = tempArray[0];
	}
	for(i=0; i<xyTemp.length; i++){
		tempArray = split(xyTemp[i], ",");
		listY[i] = tempArray[1];
	}
	meanX = listX;
	meanY = listY;
	if(type=="Z-Stack") zStitch = true;
	else zStitch = false;
	count = newArray(GX);
	Array.fill(count, 0);
	}
	processFolder(input);
	readVASTCSV(file);
	combineData(zMipPrefix, input);
}


function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	n = 0;
	for (i = 0; i< list.length; i++){
		if(endsWith(list[i], suffix)) n++;
	}
	time = newArray(n);
	processedFiles = newArray(n);
	n = 0;
	if(File.exists(input+File.separator+"Image-times.xls")){
		tempProcessed = split(File.openAsString(input+File.separator+"Image-times.xls"),"\n");
		processedNames = newArray((tempProcessed.length));
		processedTimes = newArray((tempProcessed.length));
		for(i=1, p=0; i<tempProcessed.length; i++){
			temp1 = split(tempProcessed[i], "\t");
			if(temp1[1]>0){
				processedNames[p] = temp1[0];
				processedTimes[p] = temp1[1];
				p++;
			}
		}
		processedNames = Array.trim(processedNames, p);
		processedTimes = Array.trim(processedTimes, p);
	}
	else{
		processedNames = newArray(0);
	}
	for (i = 0; i < list.length; i++) {
		showProgress(n/(list.length-processedNames.length));
		if(endsWith(list[i], suffix)){
			for(t=0, extract = true; t<processedNames.length; t++){
				if(list[i]==processedNames[t]){
					time[n] = processedTimes[t];
					extract = false;
				}
			}
			if(n==0){
  				Dialog.create("Choose File Output Prefix");
  				Dialog.addString("Prefix:", substring(list[i], 0, lastIndexOf(list[i], "_")), lengthOf(list[i]));
  				Dialog.show();
  				prefix = Dialog.getString();
			}
			if(extract == true){
				content = File.openAsRawString(input+list[i], 1000000); // Reads first 1000000 bytes of the file
				tStart = indexOf(content, "<AcquisitionTime>");
				offsetStart = indexOf(content, "</CreationDate>");
				if(tStart!=-1){
							timeTemp = substring(content,(tStart+17), (indexOf(content, "</AcquisitionTime>")));
							time[n] = replace(replace(replace(timeTemp, ":", ""), "-", ""),"T","");
							offset = substring(content,offsetStart-6, offsetStart);
							minutes = substring(offset, 4,6);
							hours = substring(offset, 1,3);
							adjustment = (parseInt(hours)*60)+(parseInt(minutes));
							script = 	"date = \""+timeTemp+"\";\n"+
							"regex = /(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2}).(\\d{7})/;\n"+
							"output = date.match(regex);\n"+
							"date = new Date(Date.UTC(output[1], output[2]-1, output[3], output[4], output[5], output[6], output[7]/10000));\n"+
							"offset = "+adjustment+";\n"+
							"date.setMinutes(date.getMinutes() + offset);\n"+
							"outdate = date.toISOString().replace(/\\.\\d{3}z/gi, \".\"+output[7]);\n"+
							"outdate;";
							timeTemp = eval("js", script);
							time[n] = replace(replace(replace(timeTemp, ":", ""), "-", ""),"T","");
				}
		        else time[n] = "N/A";
			}
			processedFiles[n] = list[i];
			n++;
		}
	}
	filesSorted = sortArrays(time, processedFiles);
	timeSorted = Array.copy(time);
	timeSorted = sortArrays(time, timeSorted);
	Array.sort(timeSorted);
	Array.show("Ordered by time", filesSorted, timeSorted);
	selectWindow("Ordered by time");
	saveAs("Results", input+File.separator+"Image-times.xls");
	run("Close");
}

function sortArraysOld(array1, array2){
	array1t = Array.copy(array1);
	for(i=0; i<array1.length;i++){
		array1t[i] = parseInt(array1t[i]);
	}
	array3 = newArray((array1.length));
	Array.sort(array1t);
	for(n=0; n<array1.length; n++){
		for(i=0; i<array1.length; i++){
			if(array1t[i]==parseInt(array1[n])) array3[i]=array2[n];
		}
	}
	return array3;
}

function sortArrays(template, toSort){ //Sorts array "toSort" based on standard ranking of template
	rankTemp = Array.rankPositions(template);
	sorted = newArray((toSort.length));
	for(n=0; n<toSort.length; n++){
		sorted[n] = toSort[rankTemp[n]];
	}
	return sorted;
}


function readVASTCSV(file){
contents = File.openAsString(file);
headings = "Well\\,Fish\\,Orientation\\,X\\(micron\\)\\,Angle\\,DateTime out trigger\\,DateTime in signal\\\n";
contents = replace(contents, headings, "");
if(lineCount == 0) firstWell = true;
fileArray = split(contents, "\n");
if(fileArray.length>lineCount){
	newLines = fileArray.length - lineCount;
	lineCount = fileArray.length;
}
if(newLines>0){
	wellTemp = newArray(newLines);
	fishNumWTemp = newArray(newLines);
	orientTemp = newArray(newLines);
	xPosTemp = newArray(newLines);
	angleTemp = newArray(newLines);
	trigOutTemp = newArray(newLines);
	trigInTemp = newArray(newLines);
	for(i=(lineCount-newLines); i<lineCount;i++){
		temp1 = split(fileArray[i], ",");
		wellTemp[i] = temp1[0];
		fishNumWTemp[i] = temp1[1];
		orientTemp[i] = temp1[2];
		xPosTemp[i] = temp1[3];
		angleTemp[i] = temp1[4];
		trigOutTemp[i] = replace(replace(replace(temp1[5], "-", ""), "T", ""), ":", "");
		trigInTemp[i] = replace(replace(replace(temp1[6], "-", ""), "T", ""), ":", "");
	}
	if(firstWell==false){
		well = Array.concat(well, wellTemp);
		fishNumW = Array.concat(fishNumW, fishNumWTemp);
		orient = Array.concat(orient, orientTemp);
		xPos = Array.concat(xPos, xPosTemp);
		angle = Array.concat(angle, angleTemp);
		trigOut = Array.concat(trigOut, trigOutTemp);
		trigIn = Array.concat(trigIn, trigInTemp);
	}
	else{
		well = wellTemp;
		fishNumW = fishNumWTemp;
		orient = orientTemp;
		xPos = xPosTemp;
		angle = angleTemp;
		trigOut = trigOutTemp;
		trigIn = trigInTemp;
	}
}
}

function combineData(zMIPPre, zStackIn){
fishNumTemp = newArray((well.length));
for(i=0; i<well.length; i++){
	fishNumTemp[i] = well[i]+"-"+fishNumW[i];
}
fishNumTemp = removeDuplicates(fishNumTemp);
tileNumTemp = removeDuplicates(xPos);
fishNumber = newArray((well.length));
newNames = newArray((well.length));
tileNumbers = newArray((well.length));
direction = newArray((well.length));
concatenated = newArray((well.length));
stitched = newArray((fishNumTemp.length));//Array to define whether the fish needs stitching or not.
stitchedWells = newArray((fishNumTemp.length));//Array showing which well the fish came from.
stitchedNames = newArray((fishNumTemp.length));//Final names for stitched fish.
stitchedTiles = newArray((fishNumTemp.length));//Do not carry over, work out on each loop
completeFish = newArray((fishNumTemp.length));//Do not carry over, work out on each loop
stitchedFishNumber = newArray((fishNumTemp.length));
for(i=0; i<well.length; i++){
	for(t=0; t<tileNumTemp.length; t++){
		if(tileNumTemp[t] == xPos[i]) tileNumbers[i] = IJ.pad(t+1,2);
	}
	if(orient[i]=="tail") direction[i] ="R"; 
	if(orient[i]=="head") direction[i] ="L";
	for(n=0; n<fishNumTemp.length; n++){
		if(fishNumTemp[n]==well[i]+"-"+fishNumW[i]){
			fishNumber[i] = n+1;
			stitchedFishNumber[n] = n+1;
			stitchedWells[n] = well[i];
			stitchedNames[n] = prefix+"_Fish#"+IJ.pad(fishNumber[i], 3)+direction[i];
			stitchedTiles[n] = stitchedTiles[n]+1;
		}
	}
	
	newNames[i] = prefix+"_Fish#"+IJ.pad(fishNumber[i], 3)+direction[i]+"_Tile#"+tileNumbers[i];
}
images = newArray((trigIn.length));
for(i=0; i<trigIn.length; i++){
	for(n=0; n<timeSorted.length; n++){
		if(timeSorted[n]>trigOut[i]){
			if(timeSorted[n]<trigIn[i]){
				if(images[i]==0) images[i] = filesSorted[n];
				else images[i] = ""+images[i]+","+filesSorted[n];
			}
		}
	}
}
//Check which images to use for stitching
for(i=0; i<images.length; i++){
	tempArray = split(images[i], ",");
	if(tempArray.length>stackNum){
		while (tempArray.length>stackNum){
			for(n=0; n<tempArray.length; n++){
				run("Bio-Formats Importer", "open=["+zMIPIn+zMIPPre+tempArray[n]+"] color_mode=Default view=Hyperstack stack_order=XYCZT");
				setBatchMode("show");
			}
			run("Tile");
			Dialog.create("Choose the "+stackNum+" files to concatenate:");
			Dialog.addCheckboxGroup(stackNum,(1+floor(tempArray.length/stackNum)),tempArray,newArray((tempArray.length)));
			Dialog.show();
			tempArray2 = newArray((tempArray.length));
			countTemp = 0;
			for(n=0; n<tempArray2.length; n++){
				tempArray2[n] = Dialog.getCheckbox();
				if(tempArray2[n] == 1) countTemp++;
			}
			tempArray3 = newArray(countTemp);
			for(n=0, c=0; n<tempArray2.length; n++){
				if(tempArray2[n] == 1){
					tempArray3[c] = tempArray[n];
					c++;
				}
			}
			if(tempArray3.length==stackNum) tempArray = tempArray3;
			close("*");
		}
		tempString = tempArray[0];
		for(s=1; s<tempArray.length; s++){
			tempString = "" + tempString + "," + tempArray[s];
		}
		images[i] = tempString;
	}
}
fileOuptut = File.getParent(stitchOutput);
Array.show(""+prefix+"_Arrays.xls",well,fishNumW, fishNumber,orient,direction,xPos,tileNumbers,angle,trigOut,trigIn,images,newNames);
selectWindow(""+prefix+"_Arrays.xls");
saveAs("Results", fileOuptut+File.separator+""+prefix+"_Arrays.xls");
if(type =="zStack"){
	zStitch = true;
	concatIn = zStackIn;
	pre = "";
}
else{
	zStitch = false;
	concatIn = zMIPIn;
	pre = zMIPPre;
}
for(i=0; i<well.length; i++){
	Array.show(""+prefix+"_Table.xls",stitchedFishNumber, stitchedWells, stitchedNames, stitchedTiles, stitched);
	if(File.exists(concatOutput+"MAX_"+newNames[i]+".tif")==true) concatenated[i]++;
	tempArray = split(images[i], ",");
	if(tempArray.length%1!=0) concatenated[i]++;
	if(BF==true && tempArray.length<4) concatenated[i]++;
	if(concatenated[i]==0){ //Only concatenate once
		if(tempArray.length>1){ //Only concatenate if there is more than one file!
			showProgress((i+1)/(well.length));
			concatFiles(concatIn, concatOutput, tempArray, newNames[i], type, pre);
			concatenated[i]++; //Note that this file has been concatenated
		}
	}
}
if(noStitch==false){
	pre = "MAX_";
	for(i=0; i<stitched.length; i++){
	Array.show(""+prefix+"_Table.xls",stitchedFishNumber, stitchedWells, stitchedNames, stitchedTiles, stitched);
  selectWindow(""+prefix+"_Table.xls");
  saveAs("Results", fileOuptut+File.separator+""+prefix+"_Table.xls");
	showProgress(i+1/(stitched.length));
		if(stitched[i]==0){
			for(n=1; n<GX+1; n++){
				if(File.exists(concatOutput+pre+stitchedNames[i]+"_Tile#0"+n+".tif")==false) completeFish[i] = 1;
			}
			if(stitchedTiles[i]>=GX){
				if(File.exists(stitchOutput+"Stitched_"+pre+stitchedNames[i]+".tif")==true || File.exists(stitchOutput+"CheckStitch_"+pre+stitchedNames[i]+".tif")==true) test=true;
				else test = false;
				if(completeFish[i]!=1 && test == false) stitchFile(concatOutput, stitchOutput, pre+stitchedNames[i]+"_Tile#0"+GX+".tif", stitchedNames[i],GX);
				else stitched[i] = "Incomplete fish";
			}
			if(File.exists(stitchOutput+"Stitched_"+pre+stitchedNames[i]+".tif")==true) stitched[i] = "Stitched";
			if(File.exists(stitchOutput+"CheckStitch_"+pre+stitchedNames[i]+".tif")==true) stitched[i] = "Stitching failed...";
		}
		close("*");
	}
	Array.show(""+prefix+"_Table.xls",stitchedFishNumber, stitchedWells, stitchedNames, stitchedTiles, stitched);
  selectWindow(""+prefix+"_Table.xls");
  saveAs("Results", fileOuptut+File.separator+""+prefix+"_Table.xls");
}
}

function addSec(longTime, sec){
	//convert seconds ms and add to time
	sec = parseFloat(sec);
	msTemp = 1000*sec;
	year = parseInt(substring(longTime, 0, 4));
	month = parseInt(substring(longTime, 5, 7));
	day = parseInt(substring(longTime, 8, 10));
	hour = parseInt(substring(longTime, 11, 13));
	min = parseInt(substring(longTime, 14, 16));
	seconds = parseInt(substring(longTime, 17, 19));
	ms = parseInt(substring(longTime, 20, 22));
	ms = ms+msTemp;
	if(ms>=1000){
		msTemp = floor(ms/1000);
		ms = ms-(msTemp*1000);
		seconds = seconds+msTemp;
	}
	if(seconds>=60){
		secTemp = floor(seconds/60);
		seconds = seconds-(secTemp*60);
		min = min+secTemp;
	}
	if(min>=60){
		minTemp = floor(min/60);
		min = min-(minTemp*60);
		hour = hour+minTemp;
	}
	if(hour>=24){
		hourTemp = floor(hour/24);
		hour = hour-(hourTemp*24);
		day = day+hourTemp;
	}
	time = ""+year+"-"+IJ.pad(month,2)+"-"+IJ.pad(day,2)+"T"+IJ.pad(hour,2)+":"+IJ.pad(min,2)+":"+IJ.pad(seconds,2)+"."+IJ.pad(ms,2);
	return time;
}
function removeDuplicates(array){ //Leave only the first copy of each value in an array
	n=0;
	tempArray = newArray((array.length));
	for(i=0; i<array.length; i++){
		presentTemp = false;
		for(s=0; s<tempArray.length; s++){
			if(tempArray[s]==array[i]) presentTemp = true;
		}
		if(presentTemp == false){
			tempArray[n] = array[i];
			n++;
		}
	}
	tempArray = Array.trim(tempArray, n);
	return tempArray;
}

function concatFiles(input, output, array, name, type, pre) {
run("Bio-Formats Importer", "open=["+input+pre+array[0]+"] color_mode=Default view=Hyperstack stack_order=XYCZT");
run("Bio-Formats Importer", "open=["+input+pre+array[1]+"] color_mode=Default view=Hyperstack stack_order=XYCZT");
run("Concatenate...", "  title=[Concatenated Stacks] image1=["+pre+array[0]+"] image2=["+pre+array[1]+"] image3=[-- None --]");
stackTemp = getImageID();
if(BF == true){
	if(stitchBF == true){
		if(array.length==4){
			run("Bio-Formats Importer", "open=["+input+pre+array[2]+"] color_mode=Default view=Hyperstack stack_order=XYCZT");
			run("Bio-Formats Importer", "open=["+input+pre+array[3]+"] color_mode=Default view=Hyperstack stack_order=XYCZT");
			run("Concatenate...", "  title=[Concatenated Stacks] image1=["+pre+array[2]+"] image2=["+pre+array[3]+"] image3=[-- None --]");
			bfTemp = getImageID();
			rename("Brightfield-Temp");
			selectImage(stackTemp);
			rename("Fluorescent-Temp");
			if(splitChannel == false){
				run("Merge Channels...", "c2=Fluorescent-Temp c4=Brightfield-Temp create");
				if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
				stackTemp = getImageID();
			}
		}
	}
}
selectImage(stackTemp);
if(type == "zStack"){
	if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
	saveAs("Tiff", output+name);
	if(splitChannel == true){
	selectImage(bfTemp);
	if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
	saveAs("Tiff", output+"BF_"+name);
	run("Z Project...", "projection=[Max Intensity]");
	if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
	saveAs("Tiff", output+"MAX_BF_"+name);
	selectImage(bfTemp);
	close();
	}
}
selectImage(stackTemp);
run("Z Project...", "projection=[Max Intensity]");
if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
saveAs("Tiff", output+"MAX_"+name);
close("*");
call("java.lang.System.gc");
}

function stitchFile(input, output, file, stitchedNames, GXt) {
	if(endsWith(stitchedNames, "R")){
		approach = "R";
		order="Right & Down                ";
	}
	if(endsWith(stitchedNames, "L")){
		approach = "L";
		order="Left & Down";
	}
	if (GXt==GX){
		open(input+file);
		imProp = newArray(6);
		imProp[4] = getWidth();
		imProp[5] = getHeight();
		getVoxelSize(imProp[0], imProp[1], imProp[2], imProp[3]); //Get the Voxel dimensions for the current image.
		close("*");
	}
	saved=0;
	tileEnding = "_Tile#0"+GX+".tif";
	In2=replace(file, GX+".tif", "{i}.tif");
	In3=replace(In2, "MAX_", "");
	outName=replace(file, tileEnding, ".tif");
	if(GXt>1){
		oLap = OverL/100;
		oLap1 = 1-oLap;
		oLap2 = 1-(2*oLap);
		preX = (2*oLap1*imProp[4])+((GXt-2)*oLap2*imProp[4])+((GXt-1)*oLap*imProp[4]);
		yLimUp = imProp[5]*1.1;
		xLimUp = preX*1.1;
		xLimLow = preX*0.9;
		print("Processing: " + input + file);
		InFile=In2;
		print(GX+" Tiles "+order);
		run("Grid/Collection stitching", "type=[Grid: row-by-row] order=["+order+"] grid_size_x="+GXt+" grid_size_y=1 tile_overlap="+OverL+" first_file_index_i=1 directory=["+input+"] file_names=["+InFile+"] output_textfile_name=TileConfiguration.txt fusion_method=[Linear Blending] regression_threshold="+RegTh+" max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50 compute_overlap subpixel_accuracy computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display] output_directory=["+output+"]");
		imXt = getWidth();
		imYt = getHeight();
		close();
		if(imXt>xLimLow && imXt<xLimUp && imYt<yLimUp){
			blindStitch(order,GXt,input,output,InFile,file,approach);
			if(approach == "L") run("Flip Horizontally", "stack");
			if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
			saveAs("Tiff", output+"Stitched_"+outName);
			close();
				if(zStitch==true){
					InFile=In3;
					blindStitch(order,GXt,input,output,InFile,file,approach);
					if(approach == "L") run("Flip Horizontally", "stack");
					outName=replace(outName, "MAX_","");
					if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
					saveAs("Tiff", output+"Stitched_"+outName);
					close();
				}
			saved = 1;
		}
	}
	if(saved==0){
		GXt=GXt-1;
		if(GXt>1){
			stitchFile(input, output, file, stitchedNames, GXt);
		}
   else {
      InFile=In3;
      blindStitch(order,GXt,input,output,In2,file,approach);
      if(approach == "L") run("Flip Horizontally", "stack");
      if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
      saveAs("Tiff", output+"CheckStitch_"+outName);
      close();
      if(zStitch==true){
        blindStitch(order,GXt,input,output,InFile,file,approach);
        if(approach == "L") run("Flip Horizontally", "stack");
        outName=replace(outName, "MAX_","");
        if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
        saveAs("Tiff", output+"CheckStitched_"+outName);
        close();
      }
    }
	}
  close("*.*");
  call("java.lang.System.gc");
}

function blindStitch(order,GXt,input,output,InFile,file,approach){
	print(InFile+"- GXt ="+GXt);
	baseName = replace(InFile, "_Tile#0\\{i\\}.tif", "");
	makeConfig(input, mipInput,approach, baseName, GXt);
	tileFile = baseName+"_TileConfiguration.txt";
	run("Grid/Collection stitching", "type=[Positions from file] order=[Defined by TileConfiguration] directory=["+input+"] layout_file=["+tileFile+"] fusion_method=[Linear Blending] regression_threshold=0.60 max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50 computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]");	
	setVoxelSize(imProp[0], imProp[1], imProp[2], imProp[3]);
	stitchedFile = getImageID();
	if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
	if(splitChannel == true && stitchBF == true){ //Adjust to take into account different pixel sizes!
		tileFileBF = baseName+"_TileConfiguration.txt";
		contents = File.openAsString(input+tileFileBF);
		if(startsWith(baseName, "MAX_")==true){
			contents = replace(contents, "MAX_", "MAX_BF_");
			tileFileBF = replace(tileFileBF,"MAX_", "MAX_BF_");
			}
		else{
			contents = replace(contents, baseName, "BF_"+baseName);
			tileFileBF = "BF_"+tileFileBF;
		}
		File.saveString(contents, input+tileFileBF);
		run("Grid/Collection stitching", "type=[Positions from file] order=[Defined by TileConfiguration] directory=["+input+"] layout_file=["+tileFileBF+"] fusion_method=[Linear Blending] regression_threshold=0.60 max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50 computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]");	
		setVoxelSize(imProp[0], imProp[1], imProp[2], imProp[3]);
		if(approach == "L") run("Flip Horizontally", "stack");
		if(Stack.isHyperstack) Stack.setDisplayMode("grayscale");
		saveAs("Tiff", output+"Stitched_BF_"+baseName);
		close();
	}
	selectImage(stitchedFile);
}

function makeConfig(input, mipInput, approach, baseName, GXt){
if(GXt>2){
	contents = File.openAsString(mipInput+"TileConfiguration.registered.txt");
	fileArray = split(contents, "\n");
	x = newArray(0);
	y = newArray(0);
	for(i=4; i<fileArray.length; i++){
		subArray = split(fileArray[i], ";");
		x = Array.concat(x, substring(subArray[2], (indexOf(subArray[2], "(")+1), lastIndexOf(subArray[2], ",")));
		y = Array.concat(y, substring(subArray[2], (indexOf(subArray[2], ",")+1), indexOf(subArray[2], ")")));
	}
	if((1<x.length)==true && (x.length<GX)==true){ // Extrapolate unknown tile positions from last two positions.
		xtemp = newArray((GX-x.length));
		ytemp = newArray((GX-x.length));
		for(i=0; i<(GX-x.length); i++){
			x1 = x[x.length-1];
			x2 = x[x.length-2];
			x3 = (i+1)*((x1)-(x2));
			xtemp[i] = (x1)+(x3);
			y1 = y[y.length-1];
			y2 = y[y.length-2];
			y3 = (i+1)*((y1)-(y2));
			ytemp[i] = (y1)+(y3);
		}
		x = Array.concat(x, xtemp);
		y = Array.concat(y, ytemp);
	}
}
if(GXt<3){ // If stitching has failed, load the current mean from previous (or default) tile positions.
	x = meanX;
	y = meanY;
}
else{ // Otherwise, add the new tile positions to the current running mean in meanX and meanY.
	meanX = movingMean(meanX, x, count);
	meanY = movingMean(meanY, y, count);
	for(i=0; i<count.length;i++) count[i] = count[i]+1;// As count is initially = 0, the first good stitch removes the default tile positions.
//	Array.show("Moving mean",meanX,meanY,count);
}
//Now write the tile configuration file.
if(startsWith(baseName, "MAX_")==true){
	dim = 2;
	ending = "";
}
else{
	dim = 3;
	ending = ", 0.0";
}
tileConfig = newArray("# Define the number of dimensions we are working on", "dim = "+dim+"", "", "# Define the image coordinates");
tile = Array.getSequence(GX);
for(i=0; i<tile.length;i++){
	tile[i] = tile[i]+1;
}
if(approach == "L"){
	tile = Array.reverse(tile);
}
tileConfig1 = newArray((x.length));
for(i=0; i<x.length; i++){
	tileConfig1[i] = baseName+"_Tile#"+IJ.pad(tile[i],2)+".tif; ; ("+x[i]+", "+y[i]+ending+")";
}
tileConfig = Array.concat(tileConfig, tileConfig1);
configTxt = "";
for(i=0; i<tileConfig.length; i++){
	configTxt = configTxt+tileConfig[i]+"\n";
}
File.saveString(configTxt, input+baseName+"_TileConfiguration.txt");
}

function movingMean(array1, array2, array3){
	for(i=0; i<array1.length; i++){
//		Array.show(array1, array2, array3);
		temp1 = array1[i]; //Current mean for position i
		temp2 = array2[i]; //New value to recalculate mean with
		temp3 = array3[i]; //Count for number of values used to calculate mean
		temp4 = (temp3*temp1)/(temp3+1);
		temp5 = (temp2)/(temp3+1);
		array1[i] = temp4 + temp5; //Calculate running mean
	}
	return array1;
}