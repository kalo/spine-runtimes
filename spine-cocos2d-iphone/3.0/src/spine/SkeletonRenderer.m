/******************************************************************************
 * Spine Runtimes Software License
 * Version 2.1
 * 
 * Copyright (c) 2013, Esoteric Software
 * All rights reserved.
 * 
 * You are granted a perpetual, non-exclusive, non-sublicensable and
 * non-transferable license to install, execute and perform the Spine Runtimes
 * Software (the "Software") solely for internal use. Without the written
 * permission of Esoteric Software (typically granted by licensing Spine), you
 * may not (a) modify, translate, adapt or otherwise create derivative works,
 * improvements of the Software or develop new applications using the Software
 * or (b) remove, delete, alter or obscure any trademarks or any copyright,
 * trademark, patent or other intellectual property or proprietary rights
 * notices on or in the Software, including any copy thereof. Redistributions
 * in binary or source form must include this license and terms.
 * 
 * THIS SOFTWARE IS PROVIDED BY ESOTERIC SOFTWARE "AS IS" AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL ESOTERIC SOFTARE BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *****************************************************************************/

#import <spine/SkeletonRenderer.h>
#import <spine/spine-cocos2d-iphone.h>
#import <spine/extension.h>
#import <spine/PolygonBatch.h>
#import "CCNode_Private.h"

static const int quadTriangles[6] = {0, 1, 2, 2, 3, 0};

@interface SkeletonRenderer (Private)
- (void) initialize:(SkeletonData*)skeletonData ownsSkeletonData:(bool)ownsSkeletonData;
@end

@implementation SkeletonRenderer

@synthesize skeleton = _skeleton;
@synthesize rootBone = _rootBone;
@synthesize timeScale = _timeScale;
@synthesize debugSlots = _debugSlots;
@synthesize debugBones = _debugBones;

+ (id) skeletonWithData:(SkeletonData*)skeletonData ownsSkeletonData:(bool)ownsSkeletonData {
	return [[[self alloc] initWithData:skeletonData ownsSkeletonData:ownsSkeletonData] autorelease];
}

+ (id) skeletonWithFile:(NSString*)skeletonDataFile atlas:(Atlas*)atlas scale:(float)scale {
	return [[[self alloc] initWithFile:skeletonDataFile atlas:atlas scale:scale] autorelease];
}

+ (id) skeletonWithFile:(NSString*)skeletonDataFile atlasFile:(NSString*)atlasFile scale:(float)scale {
	return [[[self alloc] initWithFile:skeletonDataFile atlasFile:atlasFile scale:scale] autorelease];
}

- (void) initialize:(SkeletonData*)skeletonData ownsSkeletonData:(bool)ownsSkeletonData {
	_ownsSkeletonData = ownsSkeletonData;

	_timeScale = 1;

	worldVertices = MALLOC(float, 1000); // Max number of vertices per mesh.

    batch = [[PolygonBatch createWithCapacity:2000] retain]; // Max number of vertices and triangles per batch.

	_skeleton = Skeleton_create(skeletonData);
	_rootBone = _skeleton->bones[0];

	_blendFunc.src = GL_ONE;
	_blendFunc.dst = GL_ONE_MINUS_SRC_ALPHA;
	[self setOpacityModifyRGB:YES];

	[self setShaderProgram:[[CCShaderCache sharedShaderCache] programForKey:kCCShader_PositionTextureColor]];
}

- (id) initWithData:(SkeletonData*)skeletonData ownsSkeletonData:(bool)ownsSkeletonData {
	NSAssert(skeletonData, @"skeletonData cannot be null.");

	self = [super init];
	if (!self) return nil;

	[self initialize:skeletonData ownsSkeletonData:ownsSkeletonData];

	return self;
}

- (id) initWithFile:(NSString*)skeletonDataFile atlas:(Atlas*)atlas scale:(float)scale {
	self = [super init];
	if (!self) return nil;

	SkeletonJson* json = SkeletonJson_create(atlas);
	json->scale = scale == 0 ? (1 / [CCDirector sharedDirector].contentScaleFactor) : scale;
	SkeletonData* skeletonData = SkeletonJson_readSkeletonDataFile(json, [skeletonDataFile UTF8String]);
	NSAssert(skeletonData, ([NSString stringWithFormat:@"Error reading skeleton data file: %@\nError: %s", skeletonDataFile, json->error]));
	SkeletonJson_dispose(json);
	if (!skeletonData) return 0;

	[self initialize:skeletonData ownsSkeletonData:YES];

	return self;
}

- (id) initWithFile:(NSString*)skeletonDataFile atlasFile:(NSString*)atlasFile scale:(float)scale {
	self = [super init];
	if (!self) return nil;

	_atlas = Atlas_createFromFile([atlasFile UTF8String], 0);
	NSAssert(_atlas, ([NSString stringWithFormat:@"Error reading atlas file: %@", atlasFile]));
	if (!_atlas) return 0;

	SkeletonJson* json = SkeletonJson_create(_atlas);
	json->scale = scale == 0 ? (1 / [CCDirector sharedDirector].contentScaleFactor) : scale;
	SkeletonData* skeletonData = SkeletonJson_readSkeletonDataFile(json, [skeletonDataFile UTF8String]);
	NSAssert(skeletonData, ([NSString stringWithFormat:@"Error reading skeleton data file: %@\nError: %s", skeletonDataFile, json->error]));
	SkeletonJson_dispose(json);
	if (!skeletonData) return 0;

	[self initialize:skeletonData ownsSkeletonData:YES];

	return self;
}

- (void) dealloc {
	if (_ownsSkeletonData) SkeletonData_dispose(_skeleton->data);
	if (_atlas) Atlas_dispose(_atlas);
	Skeleton_dispose(_skeleton);
    [batch release];
	FREE(worldVertices);
	[super dealloc];
}

- (void) update:(CCTime)deltaTime {
	Skeleton_update(_skeleton, deltaTime * _timeScale);
}

- (void) draw {
	CC_NODE_DRAW_SETUP();

	CCColor* nodeColor = self.color;
	_skeleton->r = nodeColor.red;
	_skeleton->g = nodeColor.green;
	_skeleton->b = nodeColor.blue;
	_skeleton->a = self.opacity;

	int additive = -1;
	ccColor4B color;
	const float* uvs = 0;
	int verticesCount = 0;
	const int* triangles = 0;
	int trianglesCount = 0;
	float r = 0, g = 0, b = 0, a = 0;
	for (int i = 0, n = _skeleton->slotCount; i < n; i++) {
		Slot* slot = _skeleton->drawOrder[i];
		if (!slot->attachment) continue;
		CCTexture *texture = 0;
		switch (slot->attachment->type) {
		case SP_ATTACHMENT_REGION: {
			spRegionAttachment* attachment = (spRegionAttachment*)slot->attachment;
			spRegionAttachment_computeWorldVertices(attachment, slot->skeleton->x, slot->skeleton->y, slot->bone, worldVertices);
			texture = [self getTextureForRegion:attachment];
			uvs = attachment->uvs;
			verticesCount = 8;
			triangles = quadTriangles;
			trianglesCount = 6;
			r = attachment->r;
			g = attachment->g;
			b = attachment->b;
			a = attachment->a;
			break;
		}
		case SP_ATTACHMENT_MESH: {
			spMeshAttachment* attachment = (spMeshAttachment*)slot->attachment;
			spMeshAttachment_computeWorldVertices(attachment, slot->skeleton->x, slot->skeleton->y, slot, worldVertices);
			texture = [self getTextureForMesh:attachment];
			uvs = attachment->uvs;
			verticesCount = attachment->verticesCount;
			triangles = attachment->triangles;
			trianglesCount = attachment->trianglesCount;
			r = attachment->r;
			g = attachment->g;
			b = attachment->b;
			a = attachment->a;
			break;
		}
		case SP_ATTACHMENT_SKINNED_MESH: {
			spSkinnedMeshAttachment* attachment = (spSkinnedMeshAttachment*)slot->attachment;
			spSkinnedMeshAttachment_computeWorldVertices(attachment, slot->skeleton->x, slot->skeleton->y, slot, worldVertices);
			texture = [self getTextureForSkinnedMesh:attachment];
			uvs = attachment->uvs;
			verticesCount = attachment->uvsCount;
			triangles = attachment->triangles;
			trianglesCount = attachment->trianglesCount;
			r = attachment->r;
			g = attachment->g;
			b = attachment->b;
			a = attachment->a;
			break;
		}
		default: ;
		}
		if (texture) {
			if (slot->data->additiveBlending != additive) {
				[batch flush];
				ccGLBlendFunc(_blendFunc.src, slot->data->additiveBlending ? GL_ONE : _blendFunc.dst);
				additive = slot->data->additiveBlending;
			}
			color.a = _skeleton->a * slot->a * a * 255;
			float multiplier = _premultipliedAlpha ? color.a : 255;
			color.r = _skeleton->r * slot->r * r * multiplier;
			color.g = _skeleton->g * slot->g * g * multiplier;
			color.b = _skeleton->b * slot->b * b * multiplier;
			[batch add:texture vertices:worldVertices uvs:uvs verticesCount:verticesCount
				triangles:triangles trianglesCount:trianglesCount color:&color];
		}
	}
	[batch flush];

	/*
	if (_debugSlots) {
		// Slots.
		ccDrawColor4B(0, 0, 255, 255);
		glLineWidth(1);
		CGPoint points[4];
		for (int i = 0, n = _skeleton->slotCount; i < n; i++) {
			Slot* slot = _skeleton->drawOrder[i];
			if (!slot->attachment || slot->attachment->type != ATTACHMENT_REGION) continue;
			RegionAttachment* attachment = (RegionAttachment*)slot->attachment;
			spRegionAttachment_computeWorldVertices(attachment, slot->skeleton->x, slot->skeleton->y, slot->bone, worldVertices);
			points[0] = ccp(worldVertices[0], worldVertices[1]);
			points[1] = ccp(worldVertices[2], worldVertices[3]);
			points[2] = ccp(worldVertices[4], worldVertices[5]);
			points[3] = ccp(worldVertices[6], worldVertices[7]);
			ccDrawPoly(points, 4, true);
		}
	}
	if (_debugBones) {
		// Bone lengths.
		glLineWidth(2);
		ccDrawColor4B(255, 0, 0, 255);
		for (int i = 0, n = _skeleton->boneCount; i < n; i++) {
			Bone *bone = _skeleton->bones[i];
			float x = bone->data->length * bone->m00 + bone->worldX;
			float y = bone->data->length * bone->m10 + bone->worldY;
			ccDrawLine(ccp(bone->worldX, bone->worldY), ccp(x, y));
		}
		// Bone origins.
		ccPointSize(4);
		ccDrawColor4B(0, 0, 255, 255); // Root bone is blue.
		for (int i = 0, n = _skeleton->boneCount; i < n; i++) {
			Bone *bone = _skeleton->bones[i];
			ccDrawPoint(ccp(bone->worldX, bone->worldY));
			if (i == 0) ccDrawColor4B(0, 255, 0, 255);
		}
	}
	*/
}

- (CCTexture*) getTextureForRegion:(RegionAttachment*)attachment {
	return (CCTexture*)((AtlasRegion*)attachment->rendererObject)->page->rendererObject;
}

- (CCTexture*) getTextureForMesh:(MeshAttachment*)attachment {
	return (CCTexture*)((AtlasRegion*)attachment->rendererObject)->page->rendererObject;
}

- (CCTexture*) getTextureForSkinnedMesh:(SkinnedMeshAttachment*)attachment {
	return (CCTexture*)((AtlasRegion*)attachment->rendererObject)->page->rendererObject;
}

- (CGRect) boundingBox {
	float minX = FLT_MAX, minY = FLT_MAX, maxX = FLT_MIN, maxY = FLT_MIN;
	float scaleX = self.scaleX;
	float scaleY = self.scaleY;
	float vertices[8];
	for (int i = 0; i < _skeleton->slotCount; ++i) {
		Slot* slot = _skeleton->slots[i];
		if (!slot->attachment || slot->attachment->type != ATTACHMENT_REGION) continue;
		RegionAttachment* attachment = (RegionAttachment*)slot->attachment;
		RegionAttachment_computeWorldVertices(attachment, slot->skeleton->x, slot->skeleton->y, slot->bone, vertices);
		minX = fmin(minX, vertices[VERTEX_X1] * scaleX);
		minY = fmin(minY, vertices[VERTEX_Y1] * scaleY);
		maxX = fmax(maxX, vertices[VERTEX_X1] * scaleX);
		maxY = fmax(maxY, vertices[VERTEX_Y1] * scaleY);
		minX = fmin(minX, vertices[VERTEX_X4] * scaleX);
		minY = fmin(minY, vertices[VERTEX_Y4] * scaleY);
		maxX = fmax(maxX, vertices[VERTEX_X4] * scaleX);
		maxY = fmax(maxY, vertices[VERTEX_Y4] * scaleY);
		minX = fmin(minX, vertices[VERTEX_X2] * scaleX);
		minY = fmin(minY, vertices[VERTEX_Y2] * scaleY);
		maxX = fmax(maxX, vertices[VERTEX_X2] * scaleX);
		maxY = fmax(maxY, vertices[VERTEX_Y2] * scaleY);
		minX = fmin(minX, vertices[VERTEX_X3] * scaleX);
		minY = fmin(minY, vertices[VERTEX_Y3] * scaleY);
		maxX = fmax(maxX, vertices[VERTEX_X3] * scaleX);
		maxY = fmax(maxY, vertices[VERTEX_Y3] * scaleY);
	}
	minX = self.position.x + minX;
	minY = self.position.y + minY;
	maxX = self.position.x + maxX;
	maxY = self.position.y + maxY;
	return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

// --- Convenience methods for Skeleton_* functions.

- (void) updateWorldTransform {
	Skeleton_updateWorldTransform(_skeleton);
}

- (void) setToSetupPose {
	Skeleton_setToSetupPose(_skeleton);
}
- (void) setBonesToSetupPose {
	Skeleton_setBonesToSetupPose(_skeleton);
}
- (void) setSlotsToSetupPose {
	Skeleton_setSlotsToSetupPose(_skeleton);
}

- (Bone*) findBone:(NSString*)boneName {
	return Skeleton_findBone(_skeleton, [boneName UTF8String]);
}

- (Slot*) findSlot:(NSString*)slotName {
	return Skeleton_findSlot(_skeleton, [slotName UTF8String]);
}

- (bool) setSkin:(NSString*)skinName {
	return (bool)Skeleton_setSkinByName(_skeleton, skinName ? [skinName UTF8String] : 0);
}

- (Attachment*) getAttachment:(NSString*)slotName attachmentName:(NSString*)attachmentName {
	return Skeleton_getAttachmentForSlotName(_skeleton, [slotName UTF8String], [attachmentName UTF8String]);
}
- (bool) setAttachment:(NSString*)slotName attachmentName:(NSString*)attachmentName {
	return (bool)Skeleton_setAttachment(_skeleton, [slotName UTF8String], [attachmentName UTF8String]);
}

// --- CCBlendProtocol

- (void) setBlendFunc:(ccBlendFunc)func {
	self.blendFunc = func;
}

- (ccBlendFunc) blendFunc {
	return _blendFunc;
}

- (void) setOpacityModifyRGB:(BOOL)value {
	_premultipliedAlpha = value;
}

- (BOOL) doesOpacityModifyRGB {
	return _premultipliedAlpha;
}

@end
