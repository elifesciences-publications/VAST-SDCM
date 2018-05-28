/*
3D_Crop v1.1
2018-04-13
Copyright (c) 13/04/2018 Jason J Early
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

var overlayList;
setBatchMode(true);

macro "3D_Crop"{
  run("ROI Manager...");
  setBatchMode("hide");
  keepOriginal = false;
  frontID = getImageID();
  originalTitle = getTitle();
  run("Select None");
  getVoxelSize(pxWidth, pxHeight, pxDepth, unit);
  pxDepth = 4;
  zScale = pxDepth/pxWidth;
  run("Z Project...", "projection=[Max Intensity]");
  frontIDMax = getImageID();
  selectImage(frontID);
  run("Reslice [/]...", "output=1.000 start=Top flip avoid");
  topID = getImageID();
  run("Z Project...", "projection=[Max Intensity]");
  topIDMax = getImageID();
  run("Scale...", "x=1 y="+zScale+" interpolation=Bilinear average create");
  topIDMaxScaled = getImageID();
  selectImage(frontID);
  run("Reslice [/]...", "output=1.000 start=Right rotate avoid");
  sideID = getImageID();
  run("Z Project...", "projection=[Max Intensity]");
  sideIDMax = getImageID();
  run("Scale...", "x="+zScale+" y=1 interpolation=Bilinear average create");
  sideIDMaxScaled = getImageID();
  getCropRois(topIDMaxScaled,sideIDMaxScaled,frontIDMax);
  print("getCropROIs complete");
  orthoMIP = getImageID();
  closeImages(""+topIDMaxScaled+","+sideIDMaxScaled+","+frontIDMax);
//  if(keepOriginal==false){
//    selectImage(frontID);
//    close();
//  }
  previousROIs = roiManager("count");
  setMinAndMax(0, 1500);
  selectImage(orthoMIP);
  run("Select None");
  setBatchMode("Show");
  waitForUser("Add ROIs denoting area to be preserved.");
  convertROIs(orthoMIP, 1/zScale);
  print("convertROIs complete");
  closeImages(""+sideIDMax+","+topIDMax+","+orthoMIP);
  cropROIs = newArray(3);
  cropROIs[0] = getROI("Side_Crop");
  cropROIs[1] = getROI("Top_Crop");
  cropROIs[2] = getROI("Front_Crop");
  print("getROI complete");
  Array.show(cropROIs);
  for(i=0; i<cropROIs.length; i++){
    if(cropROIs[i]>-1){
      print("Cropping");
      if(i==0){
        outputID = sideID;
        selectImage(topID);
        close();
      }
      selectImage(outputID);
      roiManager("select", cropROIs[i]);
      print(cropROIs[i]);
      run("Make Inverse");
      run("Set...", "value=0 stack");
      if(i==0){
        oldID = outputID;
        run("Select None");
        run("Reslice [/]...", "output=1.000 start=Top rotate avoid"); // Top from side
        run("Rotate... ", "angle=180 grid=1 interpolation=Bilinear stack");
        outputID = getImageID();
        selectImage(oldID);
        close();
      }
    }
    else if(i==0){
        outputID = topID;
        selectImage(sideID);
        close();
    }
    run("Select None");
    if(i==1){
      oldID = outputID;
      run("Reslice [/]...", "output=1.000 start=Bottom avoid"); // Front from top
      outputID = getImageID();
      selectImage(oldID);
      close();
    }
  }
  run("Select None");
  run("Duplicate...", "duplicate");
  run("Macro...", "code=v=(1-v) stack");
  imageCalculator("Multiply stack", ""+getTitle()+"",""+originalTitle+"");
  setBatchMode("exit and display");
}

function getCropRois(x,y,z){
  border = 20;
  selectImage(x);
  run("Select None");
  getDimensions(xWidth, xHeight, xChannels, xSlices, xFrames);
  selectImage(y);
  run("Select None");
  getDimensions(yWidth, yHeight, yChannels, ySlices, yFrames);
  selectImage(z);
  run("Select None");
  getDimensions(zWidth, zHeight, zChannels, zSlices, zFrames);
  overlayList = newArray(3);
  if((zSlices*ySlices*zSlices)==1&&(xFrames*yFrames*zFrames)==1&&xWidth==zWidth&&xHeight==yWidth&&zHeight==yHeight){
    setColor(255, 255, 255);
    newImage("orthoMIP", "16-bit", zWidth+yWidth+border, xHeight+zHeight+border, xChannels);
    outID = getImageID;
    if(xChannels>1){
      run("Re-order Hyperstack ...", "channels=[Slices (z)] slices=[Channels (c)] frames=[Frames (t)]");
      outID = getImageID;
    }
    for(i=1; i<xChannels+1;i++){
      selectImage(outID);
      if(xChannels>1) Stack.setChannel(i);
      copyImage(x, i);
      selectImage(outID);
      makeRectangle(0,0,xWidth,xHeight);
      run("Paste");
      if(i==1){
	      makeRectangle(0,0,xWidth,xHeight);
	      run("Properties... ", "  stroke=cyan width="+border/2+"");
	      Overlay.addSelection;
	      overlayList[0] = "0,0,"+xWidth+","+xHeight;
     }
      copyImage(y, i);
      selectImage(outID);
      makeRectangle(xWidth+border, xHeight+border, yWidth, yHeight);
      run("Paste");
      if(i==1){
	      makeRectangle(xWidth+border, xHeight+border, yWidth, yHeight);
	      run("Properties... ", "  stroke=cyan width="+border/2+"");
	      Overlay.addSelection;
	      overlayList[1] = ""+xWidth+border+","+xHeight+border+","+yWidth+","+yHeight;
      }
      copyImage(z, i);
      selectImage(outID);
      makeRectangle(0,xHeight+border,zWidth,zHeight);
      run("Paste");
      if(i==1){
	      makeRectangle(0,xHeight+border,zWidth,zHeight);
	      run("Properties... ", "  stroke=cyan width="+border/2+"");
	      Overlay.addSelection;
	      overlayList[2] = ""+0+","+xHeight+border+","+zWidth+","+zHeight;
      }
    }
    Overlay.show;
    run("Select None");
    return outID;
  }
}

function copyImage(ID, channel){
  selectImage(ID);
  if(channel>1) Stack.setChannel(channel);
  run("Select All");
  run("Copy");
}

function convertROIs(ID, scale){
  selectImage(ID);
//  info = getInfo("overlay");
//  print(info);
//  script = "string = '"+info+"';\nregex = new RegExp(\"\\\\[Rectangle, x=([\\\\d]+), y=([\\\\d]+), width=([\\\\d]+), height=([\\\\d]+)]\", \"g\");\r\nvar match;\r\nmatches = [];\r\nn = 0;\r\nwhile(match=regex.exec(string)){\r\n  matches[n] = [];\r\n  for(i=1;i<match.length;i++){\r\n    matches[n].push(match[i]);\r\n  }\r\n  n++;\r\n}\r\nout = matches.join(\":\");\nout;";
//  overlayList = split(eval("js", script), ":");
  Array.show(overlayList);
  overlayNames = newArray("Top", "Side", "Front");
  for(i=0 ; i<overlayList.length; i++){
    temp = split(overlayList[i], ",");
    roiTot = roiManager("count");
    for(n=0;n<roiTot;n++){
      makeRectangle(temp[0],temp[1],temp[2],temp[3]);
      if(roiContained(n)==true){
        roiName = overlayNames[i]+"_"+"Crop";
        yScale = 1;
        xScale = 1;
        if(i==0) yScale = scale; //Top View
        if(i==1) xScale = scale; //Side View
        scaleROI(n, xScale, yScale);
        roiManager("select", n);
        bounds = newArray(4);
        Roi.getBounds(bounds[0], bounds[1], bounds[2], bounds[3]);
        newX = (bounds[0]-temp[0])*xScale;
        newY = (bounds[1]-temp[1])*yScale;
        roiManager("select", roiManager("count")-1);
        Roi.move(newX, newY);
        Roi.setName(roiName);
        roiManager("add");
        roiManager("select", roiManager("count")-2);
        roiManager("delete");
      }
    }
  }
}

function roiContained(roi){
  roiManager("add");
  roiManager("select", roi);
  bounds = newArray(4);
  Roi.getBounds(bounds[0], bounds[1], bounds[2], bounds[3]);
  roiManager("select", roiManager("count")-1);
  out = true;
  if(Roi.contains(bounds[0], bounds[1])!=1) out = false;
  if(Roi.contains(bounds[0]+bounds[2], bounds[1]+bounds[3])!=1) out = false;
  roiManager("delete");
  return out;
}

function scaleROI(ROI, x, y){
  roiManager("select", ROI);
  Roi.getBounds(xpos, ypos, width, height);
  xPlus = ((1-x)/2)*width;
  yPlus = ((1-y)/2)*height;
  type = Roi.getType;
  if(matches(type, "rectangle")){
    makeRectangle(xpos+xPlus, ypos+yPlus, width*x, height*y);
    roiManager("add");
  }
  else if(matches(type, "oval")){
    makeOval(xpos+xPlus, ypos+yPlus, width*x, height*y);
    roiManager("add");
  }
  else{    
    xPlus = ((1-x)*xpos)+((1-x)*width*0.5);
    yPlus = ((1-y)*ypos)+((1-y)*height*0.5);
    Roi.getCoordinates(xpoints, ypoints);
    for(i=0; i<xpoints.length; i++){
      xpoints[i] = (xpoints[i]*x)+xPlus;
      ypoints[i] = (ypoints[i]*y)+yPlus;
    }
    makeSelection(type, xpoints, ypoints);
    roiManager("add");
  }
}

function countROIs(prefix){
  roiTot = roiManager("count");
  for(i=0, t=0; i<roiTot; i++){
    roiManager("select", i);
    if(indexOf(Roi.getName, prefix)>=-1) t++;
  }
  return t;
}

function getROI(name){
  roiTot = roiManager("count");
  index = -1;
  for(i=0; i<roiTot; i++){
    roiManager("select", i);
    tempName = Roi.getName;
    if(matches(tempName, name)) index = i;
  }
  return index;
}

function closeImages(IDs){
  toClose = split(IDs, ",");
  for(i=0; i<toClose.length; i++){
    toClose[i] = parseInt(toClose[i]);
    if(isOpen(toClose[i])){
      selectImage(toClose[i]);
      close();
    }
  }
}

