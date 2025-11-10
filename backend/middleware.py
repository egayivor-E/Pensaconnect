# middleware.py
from flask import jsonify, request
import logging
import traceback

logger = logging.getLogger(__name__)

def register_error_handlers(app):
    """Register error handlers for common HTTP errors."""
    
    @app.errorhandler(400)
    def bad_request(error):
        logger.warning(f"Bad request: {request.url} - {error.description if hasattr(error, 'description') else str(error)}")
        return jsonify({
            'error': 'bad_request',
            'message': 'The request was malformed or invalid',
            'path': request.path
        }), 400
    
    @app.errorhandler(401)
    def unauthorized(error):
        logger.warning(f"Unauthorized access: {request.url}")
        return jsonify({
            'error': 'unauthorized',
            'message': 'Authentication required',
            'path': request.path
        }), 401
    
    @app.errorhandler(403)
    def forbidden(error):
        logger.warning(f"Forbidden access: {request.url}")
        return jsonify({
            'error': 'forbidden',
            'message': 'You do not have permission to access this resource',
            'path': request.path
        }), 403
    
    @app.errorhandler(404)
    def not_found(error):
        logger.info(f"Resource not found: {request.url}")
        return jsonify({
            'error': 'not_found',
            'message': 'The requested resource was not found',
            'path': request.path
        }), 404
    
    @app.errorhandler(405)
    def method_not_allowed(error):
        logger.warning(f"Method not allowed: {request.method} {request.url}")
        return jsonify({
            'error': 'method_not_allowed',
            'message': 'The HTTP method is not allowed for this resource',
            'path': request.path,
            'method': request.method
        }), 405
    
    @app.errorhandler(409)
    def conflict(error):
        logger.warning(f"Conflict: {request.url} - {error.description if hasattr(error, 'description') else str(error)}")
        return jsonify({
            'error': 'conflict',
            'message': 'Resource conflict occurred',
            'path': request.path
        }), 409
    
    @app.errorhandler(422)
    def unprocessable_entity(error):
        logger.warning(f"Unprocessable entity: {request.url} - {error.description if hasattr(error, 'description') else str(error)}")
        return jsonify({
            'error': 'unprocessable_entity',
            'message': 'The request was well-formed but contains semantic errors',
            'path': request.path
        }), 422
    
    @app.errorhandler(429)
    def too_many_requests(error):
        logger.warning(f"Rate limit exceeded: {request.url}")
        return jsonify({
            'error': 'too_many_requests',
            'message': 'Too many requests, please try again later',
            'path': request.path
        }), 429
    
    @app.errorhandler(500)
    def internal_error(error):
        # Log the full traceback for internal errors
        logger.error(f"Internal server error: {request.url}")
        logger.error(f"Error: {str(error)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Don't expose internal details in production
        if app.config.get('ENV') == 'production':
            message = 'An internal server error occurred'
        else:
            message = f'An internal server error occurred: {str(error)}'
        
        return jsonify({
            'error': 'internal_server_error',
            'message': message,
            'path': request.path
        }), 500
    
    # Catch-all for any other exceptions
    @app.errorhandler(Exception)
    def handle_unexpected_error(error):
        logger.error(f"Unexpected error: {request.url}")
        logger.error(f"Error type: {type(error).__name__}")
        logger.error(f"Error message: {str(error)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        if app.config.get('ENV') == 'production':
            message = 'An unexpected error occurred'
        else:
            message = f'An unexpected error occurred: {str(error)}'
        
        return jsonify({
            'error': 'server_error',
            'message': message,
            'path': request.path
        }), 500
    
    logger.info("✅ Error handlers registered successfully")