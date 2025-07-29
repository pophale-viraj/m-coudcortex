# Use official Tomcat 9 with Java 21 pre-installed
FROM tomcat:9.0.82-jdk21-temurin

# Set maintainer label (optional but good practice)
LABEL maintainer="viraj.pophale@example.com"

# Remove default ROOT app (optional, keeps container clean)
RUN rm -rf /usr/local/tomcat/webapps/ROOT

# Create a user for running the application
RUN useradd -m m-cloudcortex

# Copy your WAR file into the webapps directory
COPY ./target/m-cloudcortex*.jar /usr/local/tomcat/webapps/

# Expose the default Tomcat port
EXPOSE 8080

# Set the user to 'makemytrip-ms' for security
USER m-cloudcortex

# Default command to run Tomcat
CMD ["catalina.sh", "run"]