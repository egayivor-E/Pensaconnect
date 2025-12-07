from flask import Blueprint, request, jsonify, current_app
from flask_mail import Mail, Message
import logging
from datetime import datetime
import os

logger = logging.getLogger(__name__)

# Create blueprint
anonymous_bp = Blueprint('anonymous_messages', __name__, url_prefix='/anonymous')

@anonymous_bp.route('/send-message', methods=['POST'])
def send_anonymous_message():
    """
    Send anonymous message to admin email
    ---
    tags:
      - Anonymous Messages
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - message
          properties:
            topic:
              type: string
              description: Message topic/category
            chat_id:
              type: string
              description: Chat session ID
            message:
              type: string
              description: The actual message content
              required: true
    responses:
      200:
        description: Message sent successfully
      400:
        description: Missing required fields
      500:
        description: Internal server error
    """
    try:
        data = request.get_json()
        
        # Validate required fields
        if not data or 'message' not in data:
            return jsonify({
                'success': False,
                'error': 'Message content is required'
            }), 400
        
        topic = data.get('topic', 'General Inquiry')
        chat_id = data.get('chat_id', 'Unknown')
        message_text = data.get('message', '').strip()
        
        if not message_text:
            return jsonify({
                'success': False,
                'error': 'Message cannot be empty'
            }), 400

        # Get admin email from config
        admin_email = current_app.config.get('ADMIN_EMAIL')
        if not admin_email:
            logger.error("ADMIN_EMAIL not configured")
            return jsonify({
                'success': False,
                'error': 'Admin email not configured'
            }), 500

        # Create email message
        mail = Mail(current_app)
        
        email_subject = f"🔒 Anonymous Message - {topic}"
        
        # Plain text version
        text_body = f"""
New Anonymous Message Received

Topic: {topic}
Chat ID: {chat_id}
Message: {message_text}

Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
IP Address: {request.remote_addr}

This message was sent from your Anonymous Chat App.
        """
        
        # HTML version
        html_body = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            margin-bottom: 20px;
        }}
        .message-box {{
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
            margin: 15px 0;
        }}
        .meta-info {{
            background: #e9ecef;
            padding: 15px;
            border-radius: 6px;
            font-size: 14px;
            margin: 15px 0;
        }}
        .footer {{
            margin-top: 20px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            font-size: 12px;
            color: #6c757d;
            text-align: center;
        }}
        .label {{
            font-weight: bold;
            color: #495057;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h2>📨 New Anonymous Message</h2>
        <p>Someone sent you a message through the anonymous chat</p>
    </div>
    
    <div class="message-box">
        <h3>💬 Message Content</h3>
        <p>{message_text}</p>
    </div>
    
    <div class="meta-info">
        <p><span class="label">📁 Topic:</span> {topic}</p>
        <p><span class="label">🆔 Chat ID:</span> {chat_id}</p>
        <p><span class="label">⏰ Timestamp:</span> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        <p><span class="label">🌐 IP Address:</span> {request.remote_addr}</p>
    </div>
    
    <div class="footer">
        <p>This message was sent from your Anonymous Chat App</p>
        <p>💡 The sender remains completely anonymous</p>
    </div>
</body>
</html>
        """
        
        msg = Message(
            subject=email_subject,
            recipients=[admin_email],
            body=text_body,
            html=html_body
        )
        
        # Send email
        mail.send(msg)
        
        logger.info(f"✅ Anonymous message sent to admin: {topic} - {chat_id}")
        
        return jsonify({
            'success': True,
            'message': 'Message sent to admin successfully',
            'data': {
                'topic': topic,
                'chat_id': chat_id,
                'timestamp': datetime.now().isoformat()
            }
        })
        
    except Exception as e:
        logger.error(f"❌ Error sending anonymous message: {str(e)}")
        return jsonify({
            'success': False,
            'error': f'Failed to send message: {str(e)}'
        }), 500

@anonymous_bp.route('/health', methods=['GET'])
def anonymous_health():
    """Health check for anonymous messages service"""
    return jsonify({
        'status': 'healthy',
        'service': 'anonymous_messages',
        'timestamp': datetime.now().isoformat()
    })