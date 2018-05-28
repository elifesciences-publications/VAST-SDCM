import ij.*;
import ij.IJ;
import ij.ImagePlus;
import ij.plugin.filter.PlugInFilter;
import ij.process.ImageProcessor;
import ij.process.FloatProcessor;

/**
 * ProcessPixels
 *
 * A template for processing each pixel of either
 * GRAY8, GRAY16 or GRAY32 images.
 */
public class D_Projector implements PlugInFilter {
	protected ImagePlus image;
    /** Image to hold z-projection. */
    private ImagePlus zProjImage = null; 
///////////////////////////////////////////////////////////////////////////////////
	/** Image to hold d-projection. */
    private ImagePlus dProjImage = null; //Added new ImagePlus to contain depth projection
    private int sliceNumber; //Added sliceNumber variable to allow for definition of current slice
    private float[] dpth; //Added dpth float[] array to be filled with pixel depth data
    private float[] fpixels;
///////////////////////////////////////////////////////////////////////////////////
	// image property members
	private int width;
	private int height;
	private int len;
	private int ptype;
	private int thresh = 0;
	private String otitle;
	private String ztitle;
	private String dtitle;
    /** Image stack to project. */
    public ImagePlus imp;
	// plugin parameters
	public double value = 0;
    private static final int BYTE_TYPE  = 0; 
    private static final int SHORT_TYPE = 1; 
    private static final int FLOAT_TYPE = 2;

	/**
	 * @see ij.plugin.filter.PlugInFilter#setup(java.lang.String, ij.ImagePlus)
	 */
	@Override
	public int setup(String arg, ImagePlus imp) {
		if (arg.equals("about")) {
			showAbout();
			return DONE;
		}
		image = imp;
		return DOES_8G | DOES_16 | DOES_32 ;
	}

	/**
	 * @see ij.plugin.filter.PlugInFilter#run(ij.process.ImageProcessor)
	 */
	@Override
	public void run(ImageProcessor ip) {
		// get width and height
		imp = IJ.getImage();
		otitle = imp.getTitle();
		width = ip.getWidth();
		height = ip.getHeight();
		len = width*height;
		FloatProcessor fp = new FloatProcessor(width,height);
		FloatProcessor fp2 = new FloatProcessor(width,height);
		fpixels = (float[])fp.getPixels();
		dpth = (float[])fp2.getPixels();
		process(imp);
		ztitle = "zMIP_"+otitle;
		dtitle = "dProj_"+otitle;
		zProjImage = makeOutputImage(imp, fp, ptype, ztitle);
		dProjImage = makeOutputImage(imp, fp2, ptype, dtitle);
		if (zProjImage!=null) {
			zProjImage.setCalibration(imp.getCalibration());
			IJ.run(zProjImage, "Grays", "");
			zProjImage.show();
		}
		if (dProjImage!=null) {
			dProjImage.setCalibration(imp.getCalibration());
			IJ.run(dProjImage, "Grays", "");
			dProjImage.show();
		}
		imp.unlock();
	}
	
    /** Generate output image whose type is same as input image. */
    private ImagePlus makeOutputImage(ImagePlus imp, FloatProcessor fp, int ptype, String title) {
		int width = imp.getWidth(); 
		int height = imp.getHeight(); 
		float[] pixels = (float[])fp.getPixels(); 
		ImageProcessor oip=null; 

		// Create output image consistent w/ type of input image.
		int size = pixels.length;
		switch (ptype) {
			case BYTE_TYPE:
				oip = imp.getProcessor().createProcessor(width,height);
				byte[] pixels8 = (byte[])oip.getPixels(); 
				for(int i=0; i<size; i++)
					pixels8[i] = (byte)pixels[i];
				break;
			case SHORT_TYPE:
				oip = imp.getProcessor().createProcessor(width,height);
				short[] pixels16 = (short[])oip.getPixels(); 
				for(int i=0; i<size; i++)
					pixels16[i] = (short)pixels[i];
				break;
			case FLOAT_TYPE:
				oip = new FloatProcessor(width, height, pixels, null);
				break;
		}
	
		// Adjust for display.
	    // Calling this on non-ByteProcessors ensures image
	    // processor is set up to correctly display image.
	    oip.resetMinAndMax(); 

		// Create new image plus object. Don't use
		// ImagePlus.createImagePlus here because there may be
		// attributes of input image that are not appropriate for
		// projection.
		return new ImagePlus(title, oip); 
    }
    
	/**
	 * Process an image.
	 *
	 * Please provide this method even if {@link ij.plugin.filter.PlugInFilter} does require it;
	 * the method {@link ij.plugin.filter.PlugInFilter#run(ij.process.ImageProcessor)} can only
	 * handle 2-dimensional data.
	 *
	 * If your plugin does not change the pixels in-place, make this method return the results and
	 * change the {@link #setup(java.lang.String, ij.ImagePlus)} method to return also the
	 * <i>DOES_NOTHING</i> flag.
	 *
	 * @param image the image (possible multi-dimensional)
	 */
	public void process(ImagePlus image) {
		// slice numbers start with 1 for historical reasons
		for (int i = 1; i <= image.getStackSize(); i++){
			sliceNumber = i;
			process(image.getStack().getProcessor(i));
		}
	}

	// Select processing method depending on image type
	public void process(ImageProcessor ip) {
		int type = image.getType();
		if (type == ImagePlus.GRAY8){
			process( (byte[]) ip.getPixels() );
			ptype = BYTE_TYPE;
		}
		else if (type == ImagePlus.GRAY16){
			process( (short[]) ip.getPixels() );
			ptype = SHORT_TYPE;
		}
		else if (type == ImagePlus.GRAY32){
			process( (float[]) ip.getPixels() );
			ptype = FLOAT_TYPE;
		}
		else {
			throw new RuntimeException("not supported");
		}
	}

	// processing of GRAY8 images
	public void process(byte[] pixels) {
		for (int y=0; y < height; y++) {
			for (int x=0; x < width; x++) {
				// process each pixel of the line
				// example: add 'number' to each pixel
				pixels[x + y * width] += (byte)value;
			}
		}
	}

	// processing of GRAY16 images
	public void process(short[] pixels) {
    	for(int i=0; i<len; i++) {
			if((pixels[i]&0xffff)>fpixels[i]){
				if((pixels[i]&0xffff)>thresh) dpth[i] = sliceNumber; //if pixel is max so far then log depth.
				fpixels[i] = pixels[i]&0xffff;
			}
    	}
	}
//	public void process(short[] pixels) {
//		for (int y=0; y < height; y++) {
//			for (int x=0; x < width; x++) {
//				// process each pixel of the line
//				// example: add 'number' to each pixel
//				pixels[x + y * width] += (short)value;
//			}
//		}
//	}

	// processing of GRAY32 images
	public void process(float[] pixels) {
		for (int y=0; y < height; y++) {
			for (int x=0; x < width; x++) {
				// process each pixel of the line
				// example: add 'number' to each pixel
				pixels[x + y * width] += (float)value;
			}
		}
	}

	void showAbout() {
		IJ.showMessage("dProject",
			"A plugin to produce a zMIP and associated depth projection."
		);
	}
}
